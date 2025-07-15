// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {IGmxMarket} from "../../interfaces/gmx/IGmxMarket.sol";

// @title MarketUtils
// @dev Library for market functions
library GmxMarketUtils {
  function getOppositeToken(address inputToken, IGmxMarket.Props memory market) internal pure returns (address) {
    if (inputToken == market.longToken) {
      return market.shortToken;
    }

    if (inputToken == market.shortToken) {
      return market.longToken;
    }

    revert("Unable to get opposite token");
  }
}
