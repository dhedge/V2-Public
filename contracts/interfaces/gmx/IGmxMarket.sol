// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.7.6;

import {IGmxPrice} from "./IGmxPrice.sol";

interface IGmxMarket {
  struct Props {
    address marketToken;
    address indexToken;
    address longToken;
    address shortToken;
  }

  struct MarketPrices {
    IGmxPrice.Price indexTokenPrice;
    IGmxPrice.Price longTokenPrice;
    IGmxPrice.Price shortTokenPrice;
  }
}
