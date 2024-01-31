// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.7.6;

import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";
import "../../interfaces/IERC20Extended.sol";
import "../../interfaces/IHasSupportedAsset.sol";
import "../../interfaces/IHasGuardInfo.sol";
import "../../interfaces/uniswapV2/IUniswapV2Pair.sol";
import "../../interfaces/velodrome/IVelodromeGauge.sol";
import "../../interfaces/velodrome/IVelodromeV2Gauge.sol";
import "../../guards/assetGuards/velodrome/VelodromeLPAssetGuard.sol";

library EasySwapperVelodromeLPHelpers {
  using SafeMathUpgradeable for uint256;

  /// @notice Unrolls univ2 compatible LP to the underlying assets
  /// @dev Returns the underlying asset addresses so that can be swapped upstream
  /// @param poolFactory The pool factory address
  /// @param lpAddress The address of the lp asset
  /// @param isV2 Whether the lp is a v2 lp or not
  /// @return assets the assets in the lp, that need to be swapped upstream, and the rewards tokens
  function unrollLpAndGetUnsupportedLpAssetsAndRewards(
    address poolFactory,
    address lpAddress,
    bool isV2
  ) internal returns (address[] memory assets) {
    uint256 lpBalance = IERC20Extended(lpAddress).balanceOf(address(this));
    if (lpBalance > 0) {
      address token0 = IUniswapV2Pair(lpAddress).token0();
      address token1 = IUniswapV2Pair(lpAddress).token1();
      // Burn is removeLiquidity.
      IERC20Extended(lpAddress).transfer(lpAddress, lpBalance);
      IUniswapV2Pair(lpAddress).burn(address(this));

      address gauge = VelodromeLPAssetGuard(IHasGuardInfo(poolFactory).getAssetGuard(lpAddress)).voter().gauges(
        lpAddress
      );
      uint256 rewardsListLength;
      if (gauge != address(0)) {
        // in Velodrome V2 gauges, there is only one reward token. Velodrome V1 gauges could have multiple reward tokens.
        rewardsListLength = isV2 ? 1 : IVelodromeGauge(gauge).rewardsListLength();
      }

      assets = new address[](2 + rewardsListLength);
      uint256 hits;

      assets[hits] = token0;
      hits++;

      assets[hits] = token1;
      hits++;

      if (gauge != address(0)) {
        if (isV2) {
          address rewardToken = IVelodromeV2Gauge(gauge).rewardToken();
          uint256 rewardBalance = IERC20Extended(rewardToken).balanceOf(address(this));
          if (rewardBalance > 0) {
            assets[hits] = rewardToken;
            hits++;
          }
        } else {
          for (uint256 i = 0; i < rewardsListLength; i++) {
            address rewardToken = IVelodromeGauge(gauge).rewards(i);
            uint256 rewardBalance = IERC20Extended(rewardToken).balanceOf(address(this));
            if (rewardBalance > 0) {
              assets[hits] = rewardToken;
              hits++;
            }
          }
        }

        uint256 reduceLength = assets.length.sub(hits);
        assembly {
          mstore(assets, sub(mload(assets), reduceLength))
        }
      }
    }
  }
}
