// SPDX-License-Identifier: MIT
pragma solidity >=0.7.6;

interface IOracleHeartbeat {
  function oracleHeartbeat() external view returns (uint256);
}
