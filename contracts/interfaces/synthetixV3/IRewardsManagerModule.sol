// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;

/**
 * @title Module for connecting rewards distributors to vaults.
 */
interface IRewardsManagerModule {
  /**
   * @notice Allows a user with appropriate permissions to claim rewards associated with a position.
   * @param accountId The id of the account that is to claim the rewards.
   * @param poolId The id of the pool to claim rewards on.
   * @param collateralType The address of the collateral used in the pool's rewards.
   * @param distributor The address of the rewards distributor associated with the rewards being claimed.
   * @return amountClaimedD18 The amount of rewards that were available for the account and thus claimed.
   */
  function claimRewards(
    uint128 accountId,
    uint128 poolId,
    address collateralType,
    address distributor
  ) external returns (uint256 amountClaimedD18);

  /**
   * @notice Allows a user with appropriate permissions to claim rewards associated with a position for rewards issued at the pool level.
   * @param accountId The id of the account that is to claim the rewards.
   * @param poolId The id of the pool to claim rewards on.
   * @param collateralType The address of the collateral used by the user to gain rewards from the pool level.
   * @param distributor The address of the rewards distributor associated with the rewards being claimed.
   * @return amountClaimedD18 The amount of rewards that were available for the account and thus claimed.
   */
  function claimPoolRewards(
    uint128 accountId,
    uint128 poolId,
    address collateralType,
    address distributor
  ) external returns (uint256 amountClaimedD18);

  /**
   * @notice Returns the amount of claimable rewards for a given accountId for a vault distributor.
   * @param accountId The id of the account to look up rewards on.
   * @param poolId The id of the pool to claim rewards on.
   * @param collateralType The address of the collateral used in the pool's rewards.
   * @param distributor The address of the rewards distributor associated with the rewards being claimed.
   * @return rewardAmount The amount of available rewards that are available for the provided account.
   */
  function getAvailableRewards(
    uint128 accountId,
    uint128 poolId,
    address collateralType,
    address distributor
  ) external view returns (uint256 rewardAmount);

  /**
   * @notice Returns the amount of claimable rewards for a given account position for a pool level distributor.
   * @param accountId The id of the account to look up rewards on.
   * @param poolId The id of the pool to claim rewards on.
   * @param collateralType The address of the collateral used in the pool's rewards.
   * @param distributor The address of the rewards distributor associated with the rewards being claimed.
   * @return rewardAmount The amount of available rewards that are available for the provided account.
   */
  function getAvailablePoolRewards(
    uint128 accountId,
    uint128 poolId,
    address collateralType,
    address distributor
  ) external returns (uint256 rewardAmount);
}
