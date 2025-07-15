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

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IUniswapV2Router} from "../interfaces/uniswapV2/IUniswapV2Router.sol";
import {IUniswapV2RouterSwapOnly} from "../interfaces/uniswapV2/IUniswapV2RouterSwapOnly.sol";

contract DhedgeSuperSwapper is IUniswapV2RouterSwapOnly {
  using SafeERC20 for IERC20;

  struct RouteHint {
    address asset;
    address intermediary;
  }

  IUniswapV2Router[] public uniV2Routers;
  mapping(address => address) public routeHints;

  constructor(IUniswapV2Router[] memory _uniV2Routers, RouteHint[] memory hints) {
    uniV2Routers = _uniV2Routers;

    for (uint256 i = 0; i < hints.length; i++) {
      routeHints[hints[i].asset] = hints[i].intermediary;
    }
  }

  /// @dev If there is an intermediary swap asset configured, and it's not the asset to swap to, we use it by default. otherwise we use the direct swap
  /// @param path The path to swap
  /// @return enhancedPath The path to swap with
  function _getRouteHint(address[] memory path) internal view returns (address[] memory enhancedPath) {
    address intermediary;
    enhancedPath = path;
    if (path.length == 2) {
      intermediary = routeHints[path[0]];
      if (intermediary == address(0)) {
        intermediary = routeHints[path[1]];
      }
      if (path[0] == intermediary || path[1] == intermediary) {
        intermediary = address(0);
      }
      if (intermediary != address(0)) {
        enhancedPath = new address[](3);
        enhancedPath[0] = path[0];
        enhancedPath[1] = intermediary;
        enhancedPath[2] = path[1];
      }
    }
  }

  // ---------- Public Functions ---------- //

  function swapExactTokensForTokens(
    uint256 amountIn,
    uint256 amountOutMin,
    address[] memory path,
    address to,
    uint256 deadline
  ) external override returns (uint256[] memory amounts) {
    // When we call swapExactTokensForTokens from the aaveLendingAssetGuard we only know how much of the collateralAsset we have
    // We don't know the expected amount out.
    // So we pass in amountOutMin = 0, the amountOutMin == 0 is hack so that we can leave that code unchanged
    address[] memory enhancedPath = _getRouteHint(path);

    (IUniswapV2Router router, uint256 uniV2BestAmountOut) = getBestAmountOutUniV2Router(amountIn, enhancedPath);

    // use Uni v2 router
    if (enhancedPath.length == 3) {
      require(
        uniV2BestAmountOut > 0 && uniV2BestAmountOut >= amountOutMin,
        encodeError("SwapRouter: invalid routing 011", enhancedPath[0], enhancedPath[2])
      ); // invalid routing with Uni v2 swapExactTokensForTokens with intermediate
    } else {
      require(
        uniV2BestAmountOut > 0 && uniV2BestAmountOut >= amountOutMin,
        encodeError("SwapRouter: invalid routing 012", enhancedPath[0], enhancedPath[1])
      ); // invalid routing with Uni v2 swapExactTokensForTokens (no intermediate)
    }

    IERC20(enhancedPath[0]).safeTransferFrom(msg.sender, address(this), amountIn);
    IERC20(enhancedPath[0]).safeIncreaseAllowance(address(router), amountIn);
    amounts = router.swapExactTokensForTokens(amountIn, amountOutMin, enhancedPath, to, deadline);
  }

  function swapTokensForExactTokens(
    uint256 expectedAmountOut,
    uint256 amountInMax,
    address[] memory path,
    address to,
    uint256 deadline
  ) external override returns (uint256[] memory amounts) {
    // When we call swapTokensForExactTokens from the aaveLendingAssetGuard we don't know the amount of weth we have
    // So we pass in amountInMax = uint256(-1), the amountInMax == uint256(-1) is hack so that we can leave that code unchanged
    address[] memory enhancedPath = _getRouteHint(path);

    (IUniswapV2Router router, uint256 uniBestAmountIn) = getBestAmountInUniV2Router(expectedAmountOut, enhancedPath);

    if (enhancedPath.length == 3) {
      require(
        uniBestAmountIn > 0 && uniBestAmountIn < uint256(-1) && uniBestAmountIn <= amountInMax,
        encodeError("SwapRouter: invalid routing 021", enhancedPath[0], enhancedPath[2])
      ); // invalid routing with Uni v2 swapTokensForExactTokens with intermediate
    } else {
      require(
        uniBestAmountIn > 0 && uniBestAmountIn < uint256(-1) && uniBestAmountIn <= amountInMax,
        encodeError("SwapRouter: invalid routing 022", enhancedPath[0], enhancedPath[1])
      ); // invalid routing with Uni v2 swapTokensForExactTokens (no intermediate)
    }

    IERC20(enhancedPath[0]).safeTransferFrom(msg.sender, address(this), uniBestAmountIn);
    IERC20(enhancedPath[0]).safeIncreaseAllowance(address(router), uniBestAmountIn);
    amounts = router.swapTokensForExactTokens(expectedAmountOut, amountInMax, enhancedPath, to, deadline);
  }

  // ========== VIEWS ========== //

  function getAmountsOut(
    uint256 amountIn,
    address[] memory path
  ) external view override returns (uint256[] memory amounts) {
    address[] memory enhancedPath = _getRouteHint(path);
    (, uint256 uniV2BestAmountOut) = getBestAmountOutUniV2Router(amountIn, enhancedPath);
    amounts = new uint256[](path.length);
    amounts[path.length - 1] = uniV2BestAmountOut;
  }

  function getBestAmountOutUniV2Router(
    uint256 amountIn,
    address[] memory path
  ) public view returns (IUniswapV2Router router, uint256 bestAmountOut) {
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

  function getBestAmountInUniV2Router(
    uint256 amountOut,
    address[] memory path
  ) public view returns (IUniswapV2Router router, uint256 bestAmountIn) {
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
    try uniV2Router.getAmountsIn(amountOut, path) returns (uint256[] memory amounts) {
      amount = amounts[0];
    } catch {
      amount = uint256(-1);
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

  function encodeError(string memory error, address from, address to) internal pure returns (string memory) {
    return string(abi.encodePacked(error, ": ", addressToString(from), ": ", addressToString(to)));
  }
}
