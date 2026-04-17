// SPDX-License-Identifier: MIT
pragma solidity >=0.7.6;

interface ICoreWriter {
  function sendRawAction(bytes calldata data) external;
}
