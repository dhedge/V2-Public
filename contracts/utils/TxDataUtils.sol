// SPDX-License-Identifier: MIT

pragma solidity >=0.7.6;

import {BytesLib} from "./BytesLib.sol";

abstract contract TxDataUtils {
  using BytesLib for bytes;

  function getMethod(bytes memory data) internal pure returns (bytes4) {
    return read4left(data, 0);
  }

  function getParams(bytes memory data) internal pure returns (bytes memory) {
    return data.slice(4, data.length - 4);
  }

  function getInput(bytes memory data, uint8 inputNum) internal pure returns (bytes32) {
    return read32(data, 32 * inputNum + 4, 32);
  }

  function getArrayLast(bytes memory data, uint8 inputNum) internal pure returns (bytes32) {
    bytes32 arrayPos = read32(data, 32 * inputNum + 4, 32);
    bytes32 arrayLen = read32(data, uint256(arrayPos) + 4, 32);
    require(arrayLen > 0, "input is not array");
    return read32(data, uint256(arrayPos) + 4 + (uint256(arrayLen) * 32), 32);
  }

  function getArrayIndex(bytes memory data, uint8 inputNum, uint8 arrayIndex) internal pure returns (bytes32) {
    bytes32 arrayPos = read32(data, 32 * inputNum + 4, 32);
    bytes32 arrayLen = read32(data, uint256(arrayPos) + 4, 32);
    require(arrayLen > 0, "input is not array");
    require(uint256(arrayLen) > arrayIndex, "invalid array position");
    return read32(data, uint256(arrayPos) + 4 + ((1 + uint256(arrayIndex)) * 32), 32);
  }

  function read4left(bytes memory data, uint256 offset) internal pure returns (bytes4 o) {
    require(data.length >= offset + 4, "Reading bytes out of bounds");
    assembly {
      o := mload(add(data, add(32, offset)))
    }
  }

  function read32(bytes memory data, uint256 offset, uint256 length) internal pure returns (bytes32 o) {
    require(data.length >= offset + length, "Reading bytes out of bounds");
    assembly {
      o := mload(add(data, add(32, offset)))
      let lb := sub(32, length)
      if lb {
        o := div(o, exp(2, mul(lb, 8)))
      }
    }
  }

  function convert32toAddress(bytes32 data) internal pure returns (address o) {
    return address(uint160(uint256(data)));
  }
}
