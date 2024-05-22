// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import "../utils/synthetixV3/libraries/WeeklyWindowsHelper.sol";
import "../utils/synthetixV3/libraries/SynthetixV3Structs.sol";

contract WeeklyWindowsHelperTest {
  function isWithinAllowedWindow(
    SynthetixV3Structs.Window calldata _window,
    uint256 _timestamp
  ) external pure returns (bool) {
    return WeeklyWindowsHelper.isWithinAllowedWindow(_window, _timestamp);
  }

  function validateWindows(SynthetixV3Structs.WeeklyWindows memory _windows) external pure {
    WeeklyWindowsHelper.validateWindows(_windows);
  }

  function validateWindow(SynthetixV3Structs.Window memory _window) external pure {
    WeeklyWindowsHelper._validateWindow(_window);
  }

  function validateTimePeriod(SynthetixV3Structs.TimePeriod memory _timePeriod) external pure {
    WeeklyWindowsHelper._validateTimePeriod(_timePeriod);
  }

  function timestampFromDate(uint256 year, uint256 month, uint256 day) external pure returns (uint256 timestamp) {
    timestamp = DateTime.timestampFromDate(year, month, day);
  }
}
