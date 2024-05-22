// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;

/// @title Interface a reward distributor.
interface IRewardDistributor {
  /// @notice Address to ERC-20 token distributed by this distributor, for display purposes only
  /// @dev Return address(0) if providing non ERC-20 rewards
  function token() external view returns (address);

  function precision() external view returns (uint256);
}
