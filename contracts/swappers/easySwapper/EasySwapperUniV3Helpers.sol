// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.7.6;

import {INonfungiblePositionManager} from "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import {UniswapV3NonfungiblePositionGuard} from "../../guards/contractGuards/uniswapV3/UniswapV3NonfungiblePositionGuard.sol";
import {IHasGuardInfo} from "../../interfaces/IHasGuardInfo.sol";
import {IPoolLogic} from "../../interfaces/IPoolLogic.sol";

library EasySwapperUniV3Helpers {
  /// @notice Determines which assets the swapper will have received when withdrawing from the pool
  /// @dev The pool unrolls v3 lps into the underlying assets and transfers them directly to the withdrawer, we need to know which assets the swapper received
  /// @param pool the pool the swapper is withdrawing from
  /// @param nonfungiblePositionManager the uni v3 nonfungiblePositionManager
  /// @return assets the assets that the pool has/had in v3 lping positions, that need to be swapped upstream
  function getUnsupportedUniV3Assets(
    address pool,
    address nonfungiblePositionManager
  ) internal view returns (address[] memory assets) {
    uint256[] memory tokenIds = UniswapV3NonfungiblePositionGuard(
      IHasGuardInfo(IPoolLogic(pool).factory()).getContractGuard(nonfungiblePositionManager)
    ).getOwnedTokenIds(pool);
    uint256 tokenIdsLength = tokenIds.length;

    // Each position has two assets
    assets = new address[](tokenIdsLength * 2);

    for (uint256 i; i < tokenIdsLength; ++i) {
      (, , address token0, address token1, , , , , , , , ) = INonfungiblePositionManager(nonfungiblePositionManager)
        .positions(tokenIds[i]);

      assets[i * 2] = token0;
      assets[i * 2 + 1] = token1;
    }
  }
}
