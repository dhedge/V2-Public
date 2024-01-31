// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;

/**
 * @title Module that allows the system owner to mark official pools.
 */
interface IPoolConfigurationModule {
  /**
   * @notice Retrieves the unique system preferred pool.
   * @return poolId The id of the pool that is currently set as preferred in the system.
   */
  function getPreferredPool() external view returns (uint128 poolId);

  /**
   * @notice Retrieves the pool that are approved by the system owner.
   * @return poolIds An array with all of the pool ids that are approved in the system.
   */
  function getApprovedPools() external view returns (uint256[] calldata poolIds);
}
