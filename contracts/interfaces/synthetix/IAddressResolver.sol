// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

interface IAddressResolver {
  function getSynth(bytes32 key) external view returns (address);

  function getAddress(bytes32 name) external view returns (address);
}
