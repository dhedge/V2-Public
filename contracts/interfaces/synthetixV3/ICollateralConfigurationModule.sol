// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

/**
 * @title Module for configuring system wide collateral.
 * @notice Allows the owner to configure collaterals at a system wide level.
 */
interface ICollateralConfigurationModule {
  struct CollateralConfiguration {
    bool depositingEnabled;
    uint256 issuanceRatioD18;
    uint256 liquidationRatioD18;
    uint256 liquidationRewardD18;
    bytes32 oracleNodeId;
    address tokenAddress;
    uint256 minDelegationD18;
  }

  /**
   * @notice Returns a list of detailed information pertaining to all collateral types registered in the system.
   * @dev Optionally returns only those that are currently enabled.
   * @param hideDisabled Wether to hide disabled collaterals or just return the full list of collaterals in the system.
   * @return collaterals The list of collateral configuration objects set in the system.
   */
  function getCollateralConfigurations(
    bool hideDisabled
  ) external view returns (CollateralConfiguration[] memory collaterals);

  /**
   * @notice Returns detailed information pertaining the specified collateral type.
   * @param collateralType The address for the collateral whose configuration is being queried.
   * @return collateral The configuration object describing the given collateral.
   */
  function getCollateralConfiguration(
    address collateralType
  ) external view returns (CollateralConfiguration memory collateral);
}
