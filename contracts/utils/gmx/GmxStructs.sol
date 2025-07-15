// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {PythPriceLib} from "../pyth/PythPriceLib.sol";
import {ChainlinkPythPriceLib} from "../chainlinkPyth/ChainlinkPythPriceLib.sol";
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

  struct GmxContractGuardConfig {
    address gmxExchangeRouter;
    address feeReceiver;
    address dataStore;
    address reader;
    address referralStorage;
  }
}
