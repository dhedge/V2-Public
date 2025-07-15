// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.7.6;
pragma experimental ABIEncoderV2;

interface IGmxOracleUtils {
  struct SetPricesParams {
    address[] tokens;
    address[] providers;
    bytes[] data;
  }
}
