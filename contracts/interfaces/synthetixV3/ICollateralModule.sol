// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;

/**
 * @title Module for managing user collateral.
 * @notice Allows users to deposit and withdraw collateral from the system.
 */
interface ICollateralModule {
  /**
   * @notice Deposits `tokenAmount` of collateral of type `collateralType` into account `accountId`.
   * @dev Anyone can deposit into anyone's active account without restriction.
   * @param accountId The id of the account that is making the deposit.
   * @param collateralType The address of the token to be deposited.
   * @param tokenAmount The amount being deposited, denominated in the token's native decimal representation.
   *
   * Emits a {Deposited} event.
   */
  function deposit(uint128 accountId, address collateralType, uint256 tokenAmount) external;

  /**
   * @notice Withdraws `tokenAmount` of collateral of type `collateralType` from account `accountId`.
   * @param accountId The id of the account that is making the withdrawal.
   * @param collateralType The address of the token to be withdrawn.
   * @param tokenAmount The amount being withdrawn, denominated in the token's native decimal representation.
   *
   * Requirements:
   *
   * - `msg.sender` must be the owner of the account, have the `ADMIN` permission, or have the `WITHDRAW` permission.
   *
   * Emits a {Withdrawn} event.
   *
   */
  function withdraw(uint128 accountId, address collateralType, uint256 tokenAmount) external;

  /**
   * @notice Returns the total values pertaining to account `accountId` for `collateralType`.
   * @param accountId The id of the account whose collateral is being queried.
   * @param collateralType The address of the collateral type whose amount is being queried.
   * @return totalDeposited The total collateral deposited in the account, denominated with 18 decimals of precision.
   * @return totalAssigned The amount of collateral in the account that is delegated to pools, denominated with 18 decimals of precision.
   * @return totalLocked The amount of collateral in the account that cannot currently be undelegated from a pool, denominated with 18 decimals of precision.
   */
  function getAccountCollateral(
    uint128 accountId,
    address collateralType
  ) external view returns (uint256 totalDeposited, uint256 totalAssigned, uint256 totalLocked);

  /**
   * @notice Returns the amount of collateral of type `collateralType` deposited with account `accountId` that can be withdrawn or delegated to pools.
   * @param accountId The id of the account whose collateral is being queried.
   * @param collateralType The address of the collateral type whose amount is being queried.
   * @return amountD18 The amount of collateral that is available for withdrawal or delegation, denominated with 18 decimals of precision.
   */
  function getAccountAvailableCollateral(
    uint128 accountId,
    address collateralType
  ) external view returns (uint256 amountD18);

  /**
   * @notice Clean expired locks from locked collateral arrays for an account/collateral type. It includes offset and items to prevent gas exhaustion. If both, offset and items, are 0 it will traverse the whole array (unlimited).
   * @param accountId The id of the account whose locks are being cleared.
   * @param collateralType The address of the collateral type to clean locks for.
   * @param offset The index of the first lock to clear.
   * @param count The number of slots to check for cleaning locks. Set to 0 to clean all locks at/after offset
   * @return cleared the number of locks that were actually expired (and therefore cleared)
   */
  function cleanExpiredLocks(
    uint128 accountId,
    address collateralType,
    uint256 offset,
    uint256 count
  ) external returns (uint256 cleared);

  /**
   * @notice Create a new lock on the given account. you must have `admin` permission on the specified account to create a lock.
   * @dev Collateral can be withdrawn from the system if it is not assigned or delegated to a pool. Collateral locks are an additional restriction that applies on top of that. I.e. if collateral is not assigned to a pool, but has a lock, it cannot be withdrawn.
   * @dev Collateral locks are initially intended for the Synthetix v2 to v3 migration, but may be used in the future by the Spartan Council, for example, to create and hand off accounts whose withdrawals from the system are locked for a given amount of time.
   * @param accountId The id of the account for which a lock is to be created.
   * @param collateralType The address of the collateral type for which the lock will be created.
   * @param amount The amount of collateral tokens to wrap in the lock being created, denominated with 18 decimals of precision.
   * @param expireTimestamp The date in which the lock will become clearable.
   */
  function createLock(uint128 accountId, address collateralType, uint256 amount, uint64 expireTimestamp) external;
}
