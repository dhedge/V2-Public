// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {GmxStructs} from "../../utils/gmx/GmxStructs.sol";
interface IGmxVirtualTokenResolver {
  function getVirtualTokenOracleSettings(
    address virtualToken
  ) external view returns (GmxStructs.VirtualTokenOracleSetting memory);
}
