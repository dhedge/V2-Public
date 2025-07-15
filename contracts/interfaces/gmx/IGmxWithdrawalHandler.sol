// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.7.6;
pragma experimental ABIEncoderV2;

import {IGmxOracleUtils} from "./IGmxOracleUtils.sol";

interface IGmxWithdrawalHandler {
  function withdrawalVault() external view returns (address withdrawalVaultAddress);
  function executeWithdrawal(bytes32 key, IGmxOracleUtils.SetPricesParams calldata oracleParams) external;
}
