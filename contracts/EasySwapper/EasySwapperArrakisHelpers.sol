// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.7.6;

import "../interfaces/IPoolLogic.sol";
import "../interfaces/IHasAssetInfo.sol";

import "../interfaces/arrakis/ILiquidityGaugeV4.sol";
import "../interfaces/arrakis/IArrakisVaultV1.sol";

library EasySwapperArrakisHelpers {
  /// @notice Determines which assets the swapper will have received when withdrawing from the pool
  /// @dev The pool unrolls arrakis assets into the underlying assets and transfers them directly to the withdrawer, we need to know which assets the swapper received
  /// @param arrakisAsset the address of the arrakis gauge
  function getArrakisAssets(address arrakisAsset) internal view returns (address[] memory assets) {
    ILiquidityGaugeV4 gauge = ILiquidityGaugeV4(arrakisAsset);
    IArrakisVaultV1 vault = IArrakisVaultV1(gauge.staking_token());

    uint256 rewardCount = gauge.reward_count();

    assets = new address[](2 + rewardCount);
    assets[0] = vault.token0();
    assets[1] = vault.token1();

    for (uint256 i = 0; i < rewardCount; i++) {
      assets[2 + i] = gauge.reward_tokens(i);
    }
  }
}
