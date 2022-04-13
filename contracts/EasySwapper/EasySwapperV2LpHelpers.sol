// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.7.6;

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";
import "../interfaces/uniswapv2/IUniswapV2Router.sol";
import "../interfaces/IHasAssetInfo.sol";
import "../interfaces/IERC20Extended.sol";
import "../interfaces/IERC20Extended.sol";
import "../interfaces/IHasSupportedAsset.sol";
import "../interfaces/uniswapv2/IUniswapV2Pair.sol";

library EasySwapperV2LpHelpers {
  using SafeMathUpgradeable for uint256;

  // Find the v3 assets that aren't in the supported list
  // natspec to come
  function unrollLpsAndGetUnsupportedLpAssets(
    address poolManagerLogic,
    IUniswapV2Router v2Router,
    address lpAddress
  ) internal returns (address[] memory assets) {
    address token0 = IUniswapV2Pair(lpAddress).token0();
    address token1 = IUniswapV2Pair(lpAddress).token1();
    uint256 bal = IERC20Extended(lpAddress).balanceOf(address(this));
    IERC20Extended(lpAddress).approve(address(v2Router), bal);
    v2Router.removeLiquidity(token0, token1, bal, 0, 0, address(this), type(uint256).max);

    assets = new address[](2);
    uint256 hits;

    // If the asset is in the supported list it will be processed by the EasySwapper by default
    if (!IHasSupportedAsset(poolManagerLogic).isSupportedAsset(token0)) {
      assets[hits] = token0;
      hits++;
    }

    // If the asset is in the supported list it will be processed by the EasySwapper by default
    if (!IHasSupportedAsset(poolManagerLogic).isSupportedAsset(token1)) {
      assets[hits] = token1;
      hits++;
    }

    uint256 reduceLength = assets.length.sub(hits);
    assembly {
      mstore(assets, sub(mload(assets), reduceLength))
    }
  }
}
// function removeLiquidity(
//   address tokenA,
//   address tokenB,
//   uint256 liquidity,
//   uint256 amountAMin,
//   uint256 amountBMin,
//   address to,
//   uint256 deadline
// ) external returns (uint256 amountA, uint256 amountB);
