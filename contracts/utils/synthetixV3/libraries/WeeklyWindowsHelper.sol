// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma abicoder v2;

import "../../../utils/synthetixV3/libraries/SynthetixV3Structs.sol";
import "../../../utils/DateTime.sol";

library WeeklyWindowsHelper {
  using DateTime for uint8;
  using DateTime for uint256;

  /// @notice Helper function to check if the timestamp is within allowed window
  /// @param _window Window of interest
  /// @param _timestamp Timestamp of interest
  /// @return isWithinAllowedWindow If the timestamp is within allowed window
  function isWithinAllowedWindow(
    SynthetixV3Structs.Window calldata _window,
    uint256 _timestamp
  ) external pure returns (bool) {
    uint256 currentDayOfWeek = _timestamp.getDayOfWeek();
    uint256 currentHour = _timestamp.getHour();

    if (currentDayOfWeek < _window.start.dayOfWeek || currentDayOfWeek > _window.end.dayOfWeek) {
      return false;
    }

    if (currentDayOfWeek == _window.start.dayOfWeek && currentHour < _window.start.hour) {
      return false;
    }

    if (currentDayOfWeek == _window.end.dayOfWeek && currentHour > _window.end.hour) {
      return false;
    }

    return true;
  }

  /// @notice Helper function to validate windows
  /// @param _windows Windows of interest
  function validateWindows(SynthetixV3Structs.WeeklyWindows memory _windows) external pure {
    _validateWindow(_windows.delegationWindow);
    _validateWindow(_windows.undelegationWindow);
  }

  /// @notice Helper function to validate window
  /// @param _window Window of interest
  function _validateWindow(SynthetixV3Structs.Window memory _window) internal pure {
    _validateTimePeriod(_window.start);
    _validateTimePeriod(_window.end);
  }

  /// @notice Helper function to validate time period
  /// @param _timePeriod Time period of interest
  function _validateTimePeriod(SynthetixV3Structs.TimePeriod memory _timePeriod) internal pure {
    _timePeriod.dayOfWeek.validateDayOfWeek();
    _timePeriod.hour.validateHour();
  }
}
