// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

interface IXRam {
  struct VestPosition {
    uint256 amount; // amount of xoRAM
    uint256 start; // start unix timestamp
    uint256 maxEnd; // start + maxVest (end timestamp)
    uint256 vestID; // vest identifier (starting from 0)
  }

  function vestInfo(address user) external view returns (VestPosition[] memory);

  /// @dev vesting xRAM --> RAM functionality
  function createVest(uint256 _amount) external;

  /// @dev handles all situations regarding exiting vests
  function exitVest(uint256 _vestID, bool _ve) external returns (bool);

  /// @dev returns the total number of individual vests the user has
  function usersTotalVests(address _user) external view returns (uint256);
}
