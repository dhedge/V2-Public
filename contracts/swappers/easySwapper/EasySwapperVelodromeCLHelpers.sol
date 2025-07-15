// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.7.6;

import {IVelodromeNonfungiblePositionManager} from "../../interfaces/velodrome/IVelodromeNonfungiblePositionManager.sol";
import {IHasGuardInfo} from "../../interfaces/IHasGuardInfo.sol";
import {IPoolLogic} from "../../interfaces/IPoolLogic.sol";
import {IVelodromeCLPool} from "../../interfaces/velodrome/IVelodromeCLPool.sol";
import {IVelodromeCLGauge} from "../../interfaces/velodrome/IVelodromeCLGauge.sol";
import {IVelodromeCLFactory} from "../../interfaces/velodrome/IVelodromeCLFactory.sol";

import {VelodromeNonfungiblePositionGuard} from "../../guards/contractGuards/velodrome/VelodromeNonfungiblePositionGuard.sol";

library EasySwapperVelodromeCLHelpers {
  /// @notice Determines which assets the swapper will have received when withdrawing from the pool
  /// @dev Returns the underlying asset addresses of Velodrome/Aerodrome NFT position(s) so that can be swapped upstream
  /// @param pool The pool the swapper is withdrawing from
  /// @param nonfungiblePositionManagerAddress The VelodromeCL nonfungiblePositionManager address
  /// @return assets The assets and rewardToken that the pool has/had in VelodromeCL NFT positions, that need to be swapper upstream
  function getUnsupportedCLAssetsAndRewards(
    address pool,
    address nonfungiblePositionManagerAddress
  ) internal view returns (address[] memory assets) {
    VelodromeNonfungiblePositionGuard guard = VelodromeNonfungiblePositionGuard(
      IHasGuardInfo(IPoolLogic(pool).factory()).getContractGuard(nonfungiblePositionManagerAddress)
    );
    uint256[] memory tokenIds = guard.getOwnedTokenIds(pool);
    uint256 tokenIdsLength = tokenIds.length;

    if (tokenIdsLength == 0) return assets;

    // Each position has two assets;
    // note: assume rewardToken is the same for each position as for Velodrome/Aerodrome CL
    assets = new address[](tokenIdsLength * 2 + 1);
    bool isRewardTokenSet;
    IVelodromeNonfungiblePositionManager nonfungiblePositionManager = IVelodromeNonfungiblePositionManager(
      nonfungiblePositionManagerAddress
    );
    for (uint256 i; i < tokenIdsLength; ++i) {
      (, , address token0, address token1, int24 tickSpacing, , , , , , , ) = nonfungiblePositionManager.positions(
        tokenIds[i]
      );
      assets[i * 2] = token0;
      assets[i * 2 + 1] = token1;

      // set rewardToken at the last index, only once
      if (!isRewardTokenSet) {
        IVelodromeCLGauge gauge = IVelodromeCLGauge(
          IVelodromeCLPool(
            IVelodromeCLFactory(nonfungiblePositionManager.factory()).getPool(token0, token1, tickSpacing)
          ).gauge()
        );
        assets[assets.length - 1] = gauge.rewardToken();
        isRewardTokenSet = true;
      }
    }
  }
}
