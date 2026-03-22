// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {PythPriceLib} from "../pyth/PythPriceLib.sol";
import {ChainlinkPythPriceLib} from "../chainlinkPyth/ChainlinkPythPriceLib.sol";

import {IGmxDataStore} from "../../interfaces/gmx/IGmxDataStore.sol";
import {IGmxReader} from "../../interfaces/gmx/IGmxReader.sol";
import {DhedgeNftTrackerStorage} from "../../utils/tracker/DhedgeNftTrackerStorage.sol";
import {IGmxReferralStorage} from "../../interfaces/gmx/IGmxReferralStorage.sol";
library GmxStructs {
  struct PoolSetting {
    address poolLogic;
    address withdrawalAsset;
  }

  enum OracleLookupType {
    None, // 0
    ChainlinkPythLib, // 1
    PythLib // 2
  }

  struct VirtualTokenOracleSetting {
    address virtualToken;
    uint256 virtualTokenMultiplier; // set the multiplier here, acording to the GMX price feed, https://arbitrum-api.gmxinfra.io/prices/tickers
    OracleLookupType oracleLookupType;
    ChainlinkPythPriceLib.OnchainOracle onchainOracle; // Chainlink oracle data
    address pythOracleContract;
    PythPriceLib.OffchainOracle pythOracleData;
  }

  struct DepositOrWithdrawalCommonParams {
    address receiver;
    address callbackContract;
    address[] longTokenSwapPath;
    address[] shortTokenSwapPath;
    bool shouldUnwrapNativeToken;
    address uiFeeReceiver;
  }

  struct GmxGuardData {
    IGmxDataStore dataStore;
    IGmxReader reader;
    address assetHandler;
    address uiFeeReceiver;
    DhedgeNftTrackerStorage nftTracker;
    IGmxReferralStorage referralStorage;
  }

  struct GmxContractGuardConfig {
    address gmxExchangeRouter;
    address feeReceiver;
    address dataStore;
    address reader;
    address referralStorage;
  }

  struct GmxAfterSwapOrderData {
    address account;
    address[] swapPath;
    address initialCollateralToken;
    uint256 initialCollateralDeltaAmount;
    uint256 minOutputAmount;
  }

  struct GmxAfterDepositData {
    address account;
    address market;
    address initialLongToken;
    address initialShortToken;
    uint256 initialLongTokenAmount;
    uint256 initialShortTokenAmount;
    uint256 minMarketTokens;
  }

  struct GmxAfterWithdrawalData {
    address account;
    address market;
    uint256 marketTokenAmount;
    uint256 minLongTokenAmount;
    uint256 minShortTokenAmount;
  }
}
