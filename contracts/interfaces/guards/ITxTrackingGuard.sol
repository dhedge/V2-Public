// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;

import {IGuard} from "./IGuard.sol";

interface ITxTrackingGuard is IGuard {
  function isTxTrackingGuard() external view returns (bool);

  function afterTxGuard(address poolManagerLogic, address to, bytes calldata data) external;
}
