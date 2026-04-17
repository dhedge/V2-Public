// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;

interface IMarketConfig {
  function hooks() external view returns (address);
  function oracleModule() external view returns (address);
  function weights() external view returns (address);
}
