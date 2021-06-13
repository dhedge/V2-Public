// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

interface IAddressResolver {
  function getAddress(bytes32 name) external view returns (address);
}
