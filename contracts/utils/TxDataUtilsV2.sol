// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title TxDataUtilsV2
/// @notice 0.8.x compatible transaction data parsing using native calldata slicing (zero-copy)
contract TxDataUtilsV2 {
  function getMethod(bytes calldata data) public pure returns (bytes4) {
    return bytes4(data[:4]);
  }

  function getParams(bytes calldata data) public pure returns (bytes calldata) {
    return data[4:];
  }
}
