// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;

interface IGuard {
  function txGuard(
    address poolManagerLogic,
    address to,
    bytes calldata data
  ) external returns (uint16 txType, bool isPublic); // TODO: eventually update `txType` to be of enum type as per ITransactionTypes
}
