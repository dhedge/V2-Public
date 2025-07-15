// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {GmxStructs} from "../../utils/gmx/GmxStructs.sol";
import {SlippageAccumulator} from "../../utils/SlippageAccumulator.sol";
import {IGmxDataStore} from "./IGmxDataStore.sol";
import {IGmxReader} from "./IGmxReader.sol";
import {IGmxReferralStorage} from "./IGmxReferralStorage.sol";
import {IGmxVirtualTokenResolver} from "./IGmxVirtualTokenResolver.sol";
import {IGmxCallbackReceiver} from "./IGmxCallbackReceiver.sol";
import {DhedgeNftTrackerStorage} from "../../utils/tracker/DhedgeNftTrackerStorage.sol";

interface IGmxExchangeRouterContractGuard is IGmxVirtualTokenResolver, IGmxCallbackReceiver {
  function dHedgePoolsWhitelist(address _account) external view returns (GmxStructs.PoolSetting memory);
  function feeReceiver() external view returns (address);
  function dataStore() external view returns (IGmxDataStore);
  function reader() external view returns (IGmxReader);
  function slippageAccumulator() external view returns (SlippageAccumulator);
  function nftTracker() external view returns (DhedgeNftTrackerStorage);
  function gmxExchangeRouter() external view returns (address);
  function referralStorage() external view returns (IGmxReferralStorage);
}
