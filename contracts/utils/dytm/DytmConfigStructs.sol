// SPDX-License-Identifier: MIT
pragma solidity >=0.7.6;
pragma experimental ABIEncoderV2;

library DytmConfigStructs {
  struct DytmConfig {
    address dytmOffice;
    address dytmPeriphery;
    address dhedgePoolFactory;
    address nftTracker;
    uint256 maxDytmMarkets;
  }
}
