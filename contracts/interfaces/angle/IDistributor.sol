// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma abicoder v2;

interface IDistributor {
  function claim(
    address[] calldata users,
    address[] calldata tokens,
    uint256[] calldata amounts,
    bytes32[][] calldata proofs
  ) external;
}
