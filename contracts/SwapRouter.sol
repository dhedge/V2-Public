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

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./interfaces/curve/ICurveCryptoSwap.sol";
import "./interfaces/uniswapv2/IUniswapV2Router.sol";
import "./interfaces/uniswapv2/IUniswapV2RouterSwapOnly.sol";

contract SwapRouter is Ownable, IUniswapV2RouterSwapOnly {
  using SafeERC20 for IERC20;

  struct CurvePoolCoin {
    address curvePool;
    address token;
    uint256 coinId;
  }

  IUniswapV2Router[] public uniV2Routers;
  ICurveCryptoSwap[] public curvePools;

  // Curve can get the token address from coinId, but not the other way around. Hence this mapping is required from token -> coinId
  mapping(address => mapping(address => uint256)) public curvePoolCoin;

  constructor(IUniswapV2Router[] memory _uniV2Routers, ICurveCryptoSwap[] memory _curvePools) Ownable() {
    uniV2Routers = _uniV2Routers;
    curvePools = _curvePools;

    // For Curve pools, map the underlying coins because this mapping doesn't exist in Curve.
    for (uint256 i = 0; i < _curvePools.length; i++) {
      // Maximum 10 coins per pool supported (can be adjusted)
      for (uint256 coinId = 0; coinId < 10; coinId++) {
        try _curvePools[i].underlying_coins(coinId) returns (address coinAddress) {
          CurvePoolCoin memory _curvePoolCoin = CurvePoolCoin(address(_curvePools[i]), coinAddress, coinId);
          _setCurvePoolCoin(_curvePoolCoin);
          // solhint-disable-next-line no-empty-blocks
        } catch {}
      }
    }
  }

  // ========== MUTATIVE FUNCTIONS ========== //

  // ---------- Owner Functions ---------- //

  function setCurvePoolCoins(CurvePoolCoin[] memory _curvePoolCoins) external onlyOwner {
    for (uint256 i = 0; i < _curvePoolCoins.length; i++) {
      setCurvePoolCoin(_curvePoolCoins[i]);
    }
  }

  function setCurvePoolCoin(CurvePoolCoin memory _curvePoolCoin) public onlyOwner {
    _setCurvePoolCoin(_curvePoolCoin);
  }

  // ---------- Public Functions ---------- //

  function swapExactTokensForTokens(
    uint256 amountIn,
    uint256 amountOutMin,
    address[] calldata path,
    address to,
    uint256 deadline
  ) external override returns (uint256[] memory amounts) {
    (uint256 uniV2RouterIndex, uint256 uniV2BestAmountOut) = getBestAmountOutUniV2Router(amountIn, path);

    (uint256 curvePoolIndex, uint256 curveBestAmountOut) = getBestAmountOutCurvePool(amountIn, path);
    // uniV2BestAmountOut = 0; // TODO: Bypasses Uniswap routing (only for testing)
    // curveBestAmountOut = 0; // TODO: Bypasses Curve routing (only for testing)

    IERC20(path[0]).transferFrom(msg.sender, address(this), amountIn);

    if (uniV2BestAmountOut > curveBestAmountOut) {
      // use Uni v2 router
      require(uniV2BestAmountOut > 0, "SwapRouter: invalid routing 01"); // invalid routing with Uni v2 swapExactTokensForTokens
      IERC20(path[0]).approve(address(uniV2Routers[uniV2RouterIndex]), amountIn);
      amounts = uniV2Routers[uniV2RouterIndex].swapExactTokensForTokens(amountIn, amountOutMin, path, to, deadline);
    } else {
      // Use Curve pool
      require(curveBestAmountOut > 0, "SwapRouter: invalid routing 03"); // invalid routing with Curve swapExactTokensForToken
      IERC20(path[0]).approve(address(curvePools[curvePoolIndex]), amountIn);
      _curveExchange(curvePoolIndex, amountIn, curveBestAmountOut, path);
      amounts = new uint256[](2);
      amounts[0] = amountIn;
      amounts[1] = curveBestAmountOut;
    }
  }

  function swapTokensForExactTokens(
    uint256 amountOut,
    uint256 amountInMax,
    address[] calldata path,
    address to,
    uint256 deadline
  ) external override returns (uint256[] memory amounts) {
    (uint256 routerIndex, uint256 bestAmountIn) = getBestAmountInUniV2Router(amountOut, path);
    require(bestAmountIn > 0, "SwapRouter: invalid routing 02"); // invalid routing with Uni v2 swapTokensForExactTokens
    require(bestAmountIn < uint256(-1), "SwapRouter: invalid routing 021"); // invalid routing with Uni v2 swapTokensForExactTokens

    IERC20(path[0]).transferFrom(msg.sender, address(this), bestAmountIn);
    IERC20(path[0]).approve(address(uniV2Routers[routerIndex]), bestAmountIn);
    amounts = uniV2Routers[routerIndex].swapTokensForExactTokens(amountOut, amountInMax, path, to, deadline);
  }

  // ---------- Internal Functions ---------- //

  function bytesToAddress(bytes memory bys) internal pure returns (address addr) {
    assembly {
      addr := mload(add(bys, 20))
    }
  }

  function _setCurvePoolCoin(CurvePoolCoin memory _curvePoolCoin) internal {
    curvePoolCoin[_curvePoolCoin.curvePool][_curvePoolCoin.token] = _curvePoolCoin.coinId;
  }

  function _curveExchange(
    uint256 curvePoolIndex,
    uint256 amountIn,
    uint256 amountOutMin,
    address[] calldata path
  ) internal {
    ICurveCryptoSwap curvePool = curvePools[curvePoolIndex];
    uint256 from = curvePoolCoin[address(curvePool)][path[0]];
    uint256 to = curvePoolCoin[address(curvePool)][path[path.length - 1]];

    curvePool.exchange_underlying(from, to, amountIn, amountOutMin);
  }

  // ========== VIEWS ========== //

  function getBestAmountOutUniV2Router(uint256 amountIn, address[] memory path)
    public
    view
    returns (uint256 routerIndex, uint256 bestAmountOut)
  {
    for (uint256 i = 0; i < uniV2Routers.length; i++) {
      uint256 amount = getAmountOutUniV2(uniV2Routers[i], amountIn, path);

      if (amount > bestAmountOut) {
        bestAmountOut = amount;
        routerIndex = i;
      }
    }
  }

  function getAmountOutUniV2(
    IUniswapV2Router uniV2Router,
    uint256 amountIn,
    address[] memory path
  ) public view returns (uint256 amount) {
    uint256[] memory amounts = new uint256[](path.length);
    amounts = uniV2Router.getAmountsOut(amountIn, path);
    return amounts[amounts.length - 1];
  }

  function getBestAmountInUniV2Router(uint256 amountOut, address[] memory path)
    public
    view
    returns (uint256 routerIndex, uint256 bestAmountIn)
  {
    bestAmountIn = uint256(-1); // first set to largest value to find lowest amountIn
    for (uint256 i = 0; i < uniV2Routers.length; i++) {
      uint256 amount = getAmountInUniV2(uniV2Routers[i], amountOut, path);

      if (amount < bestAmountIn && amount > 0) {
        bestAmountIn = amount;
        routerIndex = i;
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
    returns (uint256 poolIndex, uint256 bestAmountOut)
  {
    for (uint256 i = 0; i < curvePools.length; i++) {
      uint256 amount = getAmountOutCurve(curvePools[i], amountIn, path);

      if (amount > bestAmountOut) {
        bestAmountOut = amount;
        poolIndex = i;
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

    // Check that the coin mapping matches Curve for correct routing (especially if coinId = 0, which means it might not be set)
    if (curvePool.underlying_coins(from) != path[0]) {
      return 0; // CoinId doesn't match Curve setting. Don't use Curve.
    }

    if (curvePool.underlying_coins(to) != path[path.length - 1]) {
      return 0; // CoinId doesn't match Curve setting. Don't use Curve.
    }

    amount = curvePool.get_dy_underlying(from, to, amountIn);
  }
}
