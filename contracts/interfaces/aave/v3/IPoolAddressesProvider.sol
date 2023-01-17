// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

interface IPoolAddressesProvider {
  function getPool() external view returns (address);

  function getPriceOracle() external view returns (address);
}
