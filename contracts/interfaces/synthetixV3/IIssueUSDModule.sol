// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;

/**
 * @title Module for the minting and burning of stablecoins.
 */
interface IIssueUSDModule {
  /**
   * @notice Mints {amount} of snxUSD with the specified liquidity position.
   * @param accountId The id of the account that is minting snxUSD.
   * @param poolId The id of the pool whose collateral will be used to back up the mint.
   * @param collateralType The address of the collateral that will be used to back up the mint.
   * @param amount The amount of snxUSD to be minted, denominated with 18 decimals of precision.
   *
   * Requirements:
   *
   * - `msg.sender` must be the owner of the account, have the `ADMIN` permission, or have the `MINT` permission.
   * - After minting, the collateralization ratio of the liquidity position must not be below the target collateralization ratio for the corresponding collateral type.
   *
   * Emits a {UsdMinted} event.
   */
  function mintUsd(
    uint128 accountId,
    uint128 poolId,
    address collateralType,
    uint256 amount
  ) external;

  /**
   * @notice Burns {amount} of snxUSD with the specified liquidity position.
   * @param accountId The id of the account that is burning snxUSD.
   * @param poolId The id of the pool whose collateral was used to back up the snxUSD.
   * @param collateralType The address of the collateral that was used to back up the snxUSD.
   * @param amount The amount of snxUSD to be burnt, denominated with 18 decimals of precision.
   *
   * Emits a {UsdMinted} event.
   */
  function burnUsd(
    uint128 accountId,
    uint128 poolId,
    address collateralType,
    uint256 amount
  ) external;
}
