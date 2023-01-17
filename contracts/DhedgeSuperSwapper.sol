//
//        __  __    __  ________  _______    ______   ________
//       /  |/  |  /  |/        |/       \  /      \ /        |
//   ____$$ |$$ |  $$ |$$$$$$$$/ $$$$$$$  |/$$$$$$  |$$$$$$$$/
//  /    $$ |$$ |__$$ |$$ |__    $$ |  $$ |$$ | _$$/ $$ |__
// /$$$$$$$ |$$    $$ |$$    |   $$ |  $$ |$$ |/    |$$    |
// $$ |  $$ |$$$$$$$$ |$$$$$/    $$ |  $$ |$$ |$$$$ |$$$$$/
// $$ \__$$ |$$ |  $$ |$$ |_____ $$ |__$$ |$$ \__$$ |$$ |_____
// $$    $$ |$$ |  $$ |$$       |$$    $$/ $$    $$/ $$       |
//  $$$$$$$/ $$/   $$/ $$$$$$$$/ $$$$$$$/   $$$$$$/  $$$$$$$$/
//
// dHEDGE DAO - https://dhedge.org
//
// Copyright (c) 2022 dHEDGE DAO
//
// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma abicoder v2;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./interfaces/curve/ICurveCryptoSwap.sol";
import "./interfaces/uniswapv2/IUniswapV2Router.sol";
import "./interfaces/uniswapv2/IUniswapV2RouterSwapOnly.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

contract DhedgeSuperSwapper is IUniswapV2RouterSwapOnly {
  using SafeERC20 for IERC20;
  using SafeMath for uint256;

  event Swap(address indexed swapRouter);

  IUniswapV2Router[] public uniV2Routers;
  ICurveCryptoSwap[] public curvePools;

  // CurvePool -> tokenAddress -> coinIndex+1
  mapping(address => mapping(address => uint256)) public curvePoolCoin;

  constructor(IUniswapV2Router[] memory _uniV2Routers, ICurveCryptoSwap[] memory _curvePools) {
    uniV2Routers = _uniV2Routers;
    curvePools = _curvePools;

    // For Curve pools, map the underlying coins because this mapping doesn't exist in Curve.
    for (uint256 i = 0; i < _curvePools.length; i++) {
      // Maximum 10 coins per pool supported (can be adjusted)
      for (uint256 coinIndex = 0; coinIndex < 10; coinIndex++) {
        try _curvePools[i].underlying_coins(coinIndex) returns (address coinAddress) {
          // Use 1 based index so we can check existence later
          curvePoolCoin[address(_curvePools[i])][coinAddress] = coinIndex + 1;
          // solhint-disable-next-line no-empty-blocks
        } catch {
          break;
        }
      }
    }
  }

  // ---------- Public Functions ---------- //

  function swapExactTokensForTokens(
    uint256 amountIn,
    uint256 amountOutMin,
    address[] calldata path,
    address to,
    uint256 deadline
  ) external override returns (uint256[] memory amounts) {
    (IUniswapV2Router router, uint256 uniV2BestAmountOut) = getBestAmountOutUniV2Router(amountIn, path);
    (ICurveCryptoSwap curvePool, uint256 curveBestAmountOut) = getBestAmountOutCurvePool(amountIn, path);

    IERC20(path[0]).transferFrom(msg.sender, address(this), amountIn);

    if (curveBestAmountOut > uniV2BestAmountOut) {
      // Use Curve pool
      require(curveBestAmountOut > 0, encodeError("SwapRouter: invalid routing 03", path[0])); // invalid routing with Curve
      IERC20(path[0]).approve(address(curvePool), amountIn);
      _curveExchange(curvePool, amountIn, curveBestAmountOut, path, to);
      emit Swap(address(curvePool));
      amounts = new uint256[](2);
      amounts[0] = amountIn;
      amounts[1] = curveBestAmountOut;
    } else {
      // use Uni v2 router
      require(uniV2BestAmountOut > 0, encodeError("SwapRouter: invalid routing 01", path[0])); // invalid routing with Uni v2 swapExactTokensForTokens
      IERC20(path[0]).approve(address(router), amountIn);
      amounts = router.swapExactTokensForTokens(amountIn, amountOutMin, path, to, deadline);
      emit Swap(address(router));
    }
  }

  function swapTokensForExactTokens(
    uint256 expectedAmountOut,
    uint256 amountInMax,
    address[] calldata path,
    address to,
    uint256 deadline
  ) external override returns (uint256[] memory amounts) {
    (IUniswapV2Router router, uint256 uniBestAmountIn) = getBestAmountInUniV2Router(expectedAmountOut, path);
    require(uniBestAmountIn > 0, encodeError("SwapRouter: invalid routing 02", path[0])); // invalid routing with Uni v2 swapTokensForExactTokens
    require(uniBestAmountIn < uint256(-1), encodeError("SwapRouter: invalid routing 021", path[0])); // invalid routing with Uni v2 swapTokensForExactTokens
    require(uniBestAmountIn < amountInMax, encodeError("SwapRouter: invalid routing 022", path[0])); // invalid routing with Uni v2 swapTokensForExactTokens

    IERC20(path[0]).transferFrom(msg.sender, address(this), uniBestAmountIn);
    IERC20(path[0]).approve(address(router), uniBestAmountIn);
    amounts = router.swapTokensForExactTokens(expectedAmountOut, amountInMax, path, to, deadline);
    emit Swap(address(router));
  }

  function _curveExchange(
    ICurveCryptoSwap curvePool,
    uint256 amountIn,
    uint256 amountOutMin,
    address[] calldata path,
    address receipient
  ) internal {
    uint256 from = curvePoolCoin[address(curvePool)][path[0]];
    uint256 to = curvePoolCoin[address(curvePool)][path[path.length - 1]];

    // We use a 1 based index when storing the curve coinIndex - so we subtract 1 when using
    curvePool.exchange_underlying(from - 1, to - 1, amountIn, amountOutMin, receipient);
  }

  // ========== VIEWS ========== //

  function getAmountsOut(uint256 amountIn, address[] memory path)
    external
    view
    override
    returns (uint256[] memory amounts)
  {
    (, uint256 uniV2BestAmountOut) = getBestAmountOutUniV2Router(amountIn, path);
    (, uint256 curveBestAmountOut) = getBestAmountOutCurvePool(amountIn, path);
    amounts = new uint256[](path.length);
    amounts[path.length - 1] = curveBestAmountOut > uniV2BestAmountOut ? curveBestAmountOut : uniV2BestAmountOut;
  }

  function getBestAmountOutUniV2Router(uint256 amountIn, address[] memory path)
    public
    view
    returns (IUniswapV2Router router, uint256 bestAmountOut)
  {
    for (uint256 i = 0; i < uniV2Routers.length; i++) {
      uint256 amount = getAmountOutUniV2(uniV2Routers[i], amountIn, path);

      if (amount > bestAmountOut) {
        bestAmountOut = amount;
        router = uniV2Routers[i];
      }
    }
  }

  function getAmountOutUniV2(
    IUniswapV2Router uniV2Router,
    uint256 amountIn,
    address[] memory path
  ) public view returns (uint256 amount) {
    try uniV2Router.getAmountsOut(amountIn, path) returns (uint256[] memory amounts) {
      return amounts[amounts.length - 1];
    } catch {
      return 0;
    }
  }

  function getBestAmountInUniV2Router(uint256 amountOut, address[] memory path)
    public
    view
    returns (IUniswapV2Router router, uint256 bestAmountIn)
  {
    bestAmountIn = uint256(-1); // first set to largest value to find lowest amountIn
    for (uint256 i = 0; i < uniV2Routers.length; i++) {
      uint256 amount = getAmountInUniV2(uniV2Routers[i], amountOut, path);

      if (amount < bestAmountIn && amount > 0) {
        bestAmountIn = amount;
        router = uniV2Routers[i];
      }
    }
  }

  function getAmountInUniV2(
    IUniswapV2Router uniV2Router,
    uint256 amountOut,
    address[] memory path
  ) public view returns (uint256 amount) {
    uint256[] memory amounts = new uint256[](path.length);
    amounts = uniV2Router.getAmountsIn(amountOut, path);
    return amounts[0];
  }

  function getBestAmountOutCurvePool(uint256 amountIn, address[] memory path)
    public
    view
    returns (ICurveCryptoSwap pool, uint256 bestAmountOut)
  {
    for (uint256 i = 0; i < curvePools.length; i++) {
      uint256 amount = getAmountOutCurve(curvePools[i], amountIn, path);

      if (amount > bestAmountOut) {
        bestAmountOut = amount;
        pool = curvePools[i];
      }
    }
  }

  function getAmountOutCurve(
    ICurveCryptoSwap curvePool,
    uint256 amountIn,
    address[] memory path
  ) public view returns (uint256 amount) {
    uint256 from = curvePoolCoin[address(curvePool)][path[0]];
    uint256 to = curvePoolCoin[address(curvePool)][path[path.length - 1]];
    // If either address don't have a positive index it means their not in this pool
    if (from == 0 || to == 0) {
      amount = 0;
    } else {
      amount = curvePool.get_dy_underlying(from - 1, to - 1, amountIn).mul(999).div(1000);
    }
  }

  function addressToString(address _addr) public pure returns (string memory) {
    return toHexString(uint256(uint160(_addr)), 20);
  }

  function toHexString(uint256 value, uint256 length) internal pure returns (string memory) {
    bytes16 hexSymbols = "0123456789abcdef";
    bytes memory buffer = new bytes(2 * length + 2);
    buffer[0] = "0";
    buffer[1] = "x";
    for (uint256 i = 2 * length + 1; i > 1; --i) {
      buffer[i] = hexSymbols[value & 0xf];
      value >>= 4;
    }
    require(value == 0, "Strings: hex length insufficient");
    return string(buffer);
  }

  function encodeError(string memory error, address to) internal pure returns (string memory) {
    return string(abi.encodePacked(error, ": ", addressToString(to)));
  }
}
