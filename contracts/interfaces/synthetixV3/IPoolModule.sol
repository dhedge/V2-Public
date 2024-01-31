// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

/**
 * @title Module for the creation and management of pools.
 * @dev The pool owner can be specified during creation, can be transferred, and has credentials for configuring the pool.
 */
interface IPoolModule {
  struct PoolCollateralConfiguration {
    uint256 collateralLimitD18;
    uint256 issuanceRatioD18;
  }

  /**
   * @notice Retrieves the pool configuration of a specific collateral type.
   * @param poolId The id of the pool whose configuration is being returned.
   * @param collateralType The address of the collateral.
   * @return config The PoolCollateralConfiguration object that describes the requested collateral configuration of the pool.
   */
  function getPoolCollateralConfiguration(uint128 poolId, address collateralType)
    external
    view
    returns (PoolCollateralConfiguration memory config);
}
