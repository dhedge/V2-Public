// SPDX-License-Identifier: MIT
pragma solidity >=0.7.6;

import {INftTrackerConsumerGuard} from "../guards/INftTrackerConsumerGuard.sol";

interface IDytmOfficeContractGuard is INftTrackerConsumerGuard {
  struct WhitelistSetting {
    address poolLogic;
    bool whitelisted;
  }

  event PoolWhitelistUpdated(address indexed poolLogic, bool whitelisted);

  function dytmOffice() external view returns (address);

  function dytmPeriphery() external view returns (address);

  function poolFactory() external view returns (address);

  function poolsWhitelist(address _pool) external view returns (bool);

  function dytmMarketsWhitelist(uint88 _market) external view returns (bool);

  function getWhitelistedPools() external view returns (address[] memory);
}
