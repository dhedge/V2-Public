// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.7.6;

import "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import "../interfaces/IHasSupportedAsset.sol";
import "../interfaces/IPoolLogic.sol";

library EasySwapperV3Helpers {
  /// @notice Determines which assets the swapper will have received when withdrawing from the pool
  /// @dev The pool unrolls v3 lps into the underlying assets and transfers them directly to the withdrawer, we need to know which assets the swapper received
  /// @param pool the pool the swapper is withdrawing from
  /// @param nonfungiblePositionManager the uni v3 nonfungiblePositionManager
  /// @return assets the assets that the pool has/had in v3 lping positions, that need to be swapper upstream
  function getUnsupportedV3Assets(address pool, address nonfungiblePositionManager)
    internal
    view
    returns (address[] memory assets)
  {
    uint256 nftCount = INonfungiblePositionManager(nonfungiblePositionManager).balanceOf(pool);
    // Each position has two assets
    assets = new address[](nftCount * 2);
    for (uint256 i = 0; i < nftCount; ++i) {
      uint256 tokenId = INonfungiblePositionManager(nonfungiblePositionManager).tokenOfOwnerByIndex(pool, i);
      (, , address token0, address token1, , , , , , , , ) = INonfungiblePositionManager(nonfungiblePositionManager)
        .positions(tokenId);

      assets[i * 2] = token0;
      assets[i * 2 + 1] = token1;
    }
  }
}
