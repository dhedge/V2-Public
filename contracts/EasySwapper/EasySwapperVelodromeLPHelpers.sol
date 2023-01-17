// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.7.6;

import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";
import "../interfaces/IERC20Extended.sol";
import "../interfaces/IHasSupportedAsset.sol";
import "../interfaces/IHasGuardInfo.sol";
import "../interfaces/uniswapv2/IUniswapV2Pair.sol";
import "../interfaces/velodrome/IVelodromeGauge.sol";
import "../guards/assetGuards/VelodromeLPAssetGuard.sol";

library EasySwapperVelodromeLPHelpers {
  using SafeMathUpgradeable for uint256;

  /// @notice Unrolls univ2 compatible LP to the underlying assets
  /// @dev Returns the underlying asset addresses so that can be swapped upstream
  /// @param lpAddress The address of the lp asset
  /// @return assets the assets in the v2 lp, that need to be swapped upstream, and the rewards tokens
  function unrollLpAndGetUnsupportedLpAssetsAndRewards(address poolFactory, address lpAddress)
    internal
    returns (address[] memory assets)
  {
    uint256 bal = IERC20Extended(lpAddress).balanceOf(address(this));
    if (bal > 0) {
      address token0 = IUniswapV2Pair(lpAddress).token0();
      address token1 = IUniswapV2Pair(lpAddress).token1();
      // Burn is removeLiquidity.
      IERC20Extended(lpAddress).transfer(lpAddress, bal);
      IUniswapV2Pair(lpAddress).burn(address(this));

      IVelodromeGauge gauge = IVelodromeGauge(
        VelodromeLPAssetGuard(IHasGuardInfo(poolFactory).getAssetGuard(lpAddress)).voter().gauges(lpAddress)
      );
      uint256 rewardsListLength = address(gauge) == address(0) ? 0 : gauge.rewardsListLength();

      assets = new address[](2 + rewardsListLength);
      uint256 hits;

      assets[hits] = token0;
      hits++;

      assets[hits] = token1;
      hits++;

      for (uint256 i = 0; i < rewardsListLength; i++) {
        address rewardToken = gauge.rewards(i);
        uint256 rewardBal = IERC20Extended(rewardToken).balanceOf(address(this));
        if (rewardBal > 0) {
          assets[hits] = rewardToken;
          hits++;
        }
      }

      uint256 reduceLength = assets.length.sub(hits);
      assembly {
        mstore(assets, sub(mload(assets), reduceLength))
      }
    }
  }
}
