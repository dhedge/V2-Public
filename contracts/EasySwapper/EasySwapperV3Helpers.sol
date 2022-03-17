// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.7.6;

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";
import "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import "../interfaces/IHasSupportedAsset.sol";
import "../interfaces/IPoolLogic.sol";

// library with helper methods for oracles that are concerned with computing average prices
library EasySwapperV3Helpers {
  using SafeMathUpgradeable for uint256;

  // Find the v3 assets that aren't in the supported list
  // natspec to come
  function getUnsupportedV3Assets(address pool, address nonfungiblePositionManager)
    internal
    view
    returns (address[] memory assets)
  {
    uint256 nftCount = INonfungiblePositionManager(nonfungiblePositionManager).balanceOf(pool);
    // Each position has two assets
    assets = new address[](nftCount.mul(2));
    uint256 hits;
    for (uint256 i = 0; i < nftCount; ++i) {
      uint256 tokenId = INonfungiblePositionManager(nonfungiblePositionManager).tokenOfOwnerByIndex(pool, i);
      (, , address token0, address token1, , , , , , , , ) = INonfungiblePositionManager(nonfungiblePositionManager)
        .positions(tokenId);

      // If the asset is in the supported list it will be processed by the EasySwapper by default
      if (!IHasSupportedAsset(IPoolLogic(pool).poolManagerLogic()).isSupportedAsset(token0)) {
        assets[hits] = token0;
        hits++;
      }
      // If the asset is in the supported list it will be processed by the EasySwapper by default
      if (!IHasSupportedAsset(IPoolLogic(pool).poolManagerLogic()).isSupportedAsset(token1)) {
        assets[hits] = token1;
        hits++;
      }
    }
    uint256 reduceLength = assets.length.sub(hits);
    assembly {
      mstore(assets, sub(mload(assets), reduceLength))
    }
  }
}
