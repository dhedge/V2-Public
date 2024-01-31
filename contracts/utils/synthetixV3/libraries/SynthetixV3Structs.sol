// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;

library SynthetixV3Structs {
  struct VaultSetting {
    address poolLogic;
    address collateralAsset;
    address debtAsset;
    uint128 snxLiquidityPoolId;
  }

  /// @dev Couldn't find a way to get a mapping from synthAddress to its markedId, so storing it in guard's storage
  /// @dev Was looking for something like getSynth() but reversed
  struct AllowedMarket {
    uint128 marketId;
    address collateralSynth;
    address collateralAsset;
  }

  struct TimePeriod {
    uint8 dayOfWeek;
    uint8 hour;
  }

  struct Window {
    TimePeriod start;
    TimePeriod end;
  }

  struct WeeklyWindows {
    Window delegationWindow;
    Window undelegationWindow;
  }

  struct WeeklyWithdrawalLimit {
    uint256 usdValue;
    uint256 percent;
  }
}
