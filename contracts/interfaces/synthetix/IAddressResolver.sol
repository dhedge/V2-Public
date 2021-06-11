// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

interface IAddressResolver {
  function getAddress(bytes32 name) external view returns (address);
}
