// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

interface ILendingL2Pool {
  function getReserveAddressById(uint16 id) external view returns (address);
}
