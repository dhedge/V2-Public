// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

/* https://github.com/bokkypoobah/BokkyPooBahsDateTimeLibrary/blob/master/contracts/BokkyPooBahsDateTimeLibrary.sol */
library DateTime {
  uint256 public constant SECONDS_PER_HOUR = 60 * 60;
  uint256 public constant SECONDS_PER_DAY = SECONDS_PER_HOUR * 24;
  int256 public constant OFFSET19700101 = 2440588;

  /// @notice 1 = Monday, 7 = Sunday
  function getDayOfWeek(uint256 timestamp) internal pure returns (uint256 dayOfWeek) {
    uint256 _days = timestamp / SECONDS_PER_DAY;
    dayOfWeek = ((_days + 3) % 7) + 1;
  }

  /// @notice 0...23
  function getHour(uint256 timestamp) internal pure returns (uint256 hour) {
    uint256 secs = timestamp % SECONDS_PER_DAY;
    hour = secs / SECONDS_PER_HOUR;
  }

  /// @notice 1 = Monday, 7 = Sunday
  function validateDayOfWeek(uint8 dayOfWeek) internal pure {
    require(dayOfWeek > 0 && dayOfWeek < 8, "invalid day of week");
  }

  /// @notice 0...23
  function validateHour(uint8 hour) internal pure {
    require(hour < 24, "invalid hour");
  }

  function timestampFromDate(
    uint256 year,
    uint256 month,
    uint256 day
  ) internal pure returns (uint256 timestamp) {
    timestamp = _daysFromDate(year, month, day) * SECONDS_PER_DAY;
  }

  function _daysFromDate(
    uint256 year,
    uint256 month,
    uint256 day
  ) internal pure returns (uint256 _days) {
    require(year >= 1970, "1970 and later only");
    int256 _year = int256(year);
    int256 _month = int256(month);
    int256 _day = int256(day);

    int256 __days = _day -
      32075 +
      (1461 * (_year + 4800 + (_month - 14) / 12)) /
      4 +
      (367 * (_month - 2 - ((_month - 14) / 12) * 12)) /
      12 -
      (3 * ((_year + 4900 + (_month - 14) / 12) / 100)) /
      4 -
      OFFSET19700101;

    _days = uint256(__days);
  }
}
