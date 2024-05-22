// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

/**
 * @title Module for managing accounts.
 * @notice Manages the system's account token NFT. Every user will need to register an account before being able to interact with the system.
 */
interface IAccountModule {
  /**
   * @dev Data structure for tracking each user's permissions.
   */
  struct AccountPermissions {
    address user;
    bytes32[] permissions;
  }

  /**
   * @notice Returns an array of `AccountPermission` for the provided `accountId`.
   * @param accountId The id of the account whose permissions are being retrieved.
   * @return accountPerms An array of AccountPermission objects describing the permissions granted to the account.
   */
  function getAccountPermissions(uint128 accountId) external view returns (AccountPermissions[] memory accountPerms);

  /**
   * @notice Mints an account token with id `requestedAccountId` to `msg.sender`.
   * @param requestedAccountId The id requested for the account being created. Reverts if id already exists.
   *
   * Requirements:
   *
   * - `requestedAccountId` must not already be minted.
   * - `requestedAccountId` must be less than type(uint128).max / 2
   *
   * Emits a {AccountCreated} event.
   */
  function createAccount(uint128 requestedAccountId) external;

  /**
   * @notice Mints an account token with an available id to `msg.sender`.
   *
   * Emits a {AccountCreated} event.
   */
  function createAccount() external returns (uint128 accountId);

  /**
   * @notice Called by AccountTokenModule to notify the system when the account token is transferred.
   * @dev Resets user permissions and assigns ownership of the account token to the new holder.
   * @param to The new holder of the account NFT.
   * @param accountId The id of the account that was just transferred.
   *
   * Requirements:
   *
   * - `msg.sender` must be the account token.
   */
  function notifyAccountTransfer(address to, uint128 accountId) external;

  /**
   * @notice Grants `permission` to `user` for account `accountId`.
   * @param accountId The id of the account that granted the permission.
   * @param permission The bytes32 identifier of the permission.
   * @param user The target address that received the permission.
   *
   * Requirements:
   *
   * - `msg.sender` must own the account token with ID `accountId` or have the "admin" permission.
   *
   * Emits a {PermissionGranted} event.
   */
  function grantPermission(uint128 accountId, bytes32 permission, address user) external;

  /**
   * @notice Revokes `permission` from `user` for account `accountId`.
   * @param accountId The id of the account that revoked the permission.
   * @param permission The bytes32 identifier of the permission.
   * @param user The target address that no longer has the permission.
   *
   * Requirements:
   *
   * - `msg.sender` must own the account token with ID `accountId` or have the "admin" permission.
   *
   * Emits a {PermissionRevoked} event.
   */
  function revokePermission(uint128 accountId, bytes32 permission, address user) external;

  /**
   * @notice Revokes `permission` from `msg.sender` for account `accountId`.
   * @param accountId The id of the account whose permission was renounced.
   * @param permission The bytes32 identifier of the permission.
   *
   * Emits a {PermissionRevoked} event.
   */
  function renouncePermission(uint128 accountId, bytes32 permission) external;

  /**
   * @notice Returns `true` if `user` has been granted `permission` for account `accountId`.
   * @param accountId The id of the account whose permission is being queried.
   * @param permission The bytes32 identifier of the permission.
   * @param user The target address whose permission is being queried.
   * @return hasPermission A boolean with the response of the query.
   */
  function hasPermission(uint128 accountId, bytes32 permission, address user) external view returns (bool);

  /**
   * @notice Returns `true` if `target` is authorized to `permission` for account `accountId`.
   * @param accountId The id of the account whose permission is being queried.
   * @param permission The bytes32 identifier of the permission.
   * @param target The target address whose permission is being queried.
   * @return isAuthorized A boolean with the response of the query.
   */
  function isAuthorized(uint128 accountId, bytes32 permission, address target) external view returns (bool);

  /**
   * @notice Returns the address for the account token used by the module.
   * @return accountNftToken The address of the account token.
   */
  function getAccountTokenAddress() external view returns (address accountNftToken);

  /**
   * @notice Returns the address that owns a given account, as recorded by the system.
   * @param accountId The account id whose owner is being retrieved.
   * @return owner The owner of the given account id.
   */
  function getAccountOwner(uint128 accountId) external view returns (address owner);

  /**
   * @notice Returns the last unix timestamp that a permissioned action was taken with this account
   * @param accountId The account id to check
   * @return timestamp The unix timestamp of the last time a permissioned action occured with the account
   */
  function getAccountLastInteraction(uint128 accountId) external view returns (uint256 timestamp);
}
