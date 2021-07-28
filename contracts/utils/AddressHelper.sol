//        __  __    __  ________  _______    ______   ________
//       /  |/  |  /  |/        |/       \  /      \ /        |
//   ____$$ |$$ |  $$ |$$$$$$$$/ $$$$$$$  |/$$$$$$  |$$$$$$$$/
//  /    $$ |$$ |__$$ |$$ |__    $$ |  $$ |$$ | _$$/ $$ |__
// /$$$$$$$ |$$    $$ |$$    |   $$ |  $$ |$$ |/    |$$    |
// $$ |  $$ |$$$$$$$$ |$$$$$/    $$ |  $$ |$$ |$$$$ |$$$$$/
// $$ \__$$ |$$ |  $$ |$$ |_____ $$ |__$$ |$$ \__$$ |$$ |_____
// $$    $$ |$$ |  $$ |$$       |$$    $$/ $$    $$/ $$       |
//  $$$$$$$/ $$/   $$/ $$$$$$$$/ $$$$$$$/   $$$$$$/  $$$$$$$$/
//
// dHEDGE DAO - https://dhedge.org
//
// Copyright (c) 2021 dHEDGE DAO
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//
// SPDX-License-Identifier: MIT

// import "./BytesLib.sol";

pragma solidity 0.7.6;

/**
 * @title A library for Address utils.
 */
library AddressHelper {
  /**
   * @notice try a contract call via assembly
   * @param to the contract address
   * @param data the call data
   * @return success if the contract call is successful or not
   */
  function tryAssemblyCall(address to, bytes memory data) internal returns (bool success) {
    assembly {
      success := call(gas(), to, 0, add(data, 0x20), mload(data), 0, 0)
      switch iszero(success)
        case 1 {
          let size := returndatasize()
          returndatacopy(0x00, 0x00, size)
          revert(0x00, size)
        }
    }
  }

  /**
   * @notice try a contract delegatecall via assembly
   * @param to the contract address
   * @param data the call data
   * @return success if the contract call is successful or not
   */
  function tryAssemblyDelegateCall(address to, bytes memory data) internal returns (bool success) {
    assembly {
      success := delegatecall(gas(), to, add(data, 0x20), mload(data), 0, 0)
      switch iszero(success)
        case 1 {
          let size := returndatasize()
          returndatacopy(0x00, 0x00, size)
          revert(0x00, size)
        }
    }
  }

  // /**
  //  * @notice try a contract call
  //  * @param to the contract address
  //  * @param data the call data
  //  * @return success if the contract call is successful or not
  //  */
  // function tryCall(address to, bytes memory data) internal returns (bool) {
  //   (bool success, bytes memory res) = to.call(data);

  //   // Get the revert message of the call and revert with it if the call failed
  //   require(success, _getRevertMsg(res));

  //   return success;
  // }

  // /**
  //  * @dev Get the revert message from a call
  //  * @notice This is needed in order to get the human-readable revert message from a call
  //  * @param response Response of the call
  //  * @return Revert message string
  //  */
  // function _getRevertMsg(bytes memory response) internal pure returns (string memory) {
  //     // If the response length is less than 68, then the transaction failed silently (without a revert message)
  //     if (response.length < 68) return "Transaction reverted silently";
  //     bytes memory revertData = response.slice(4, response.length - 4); // Remove the selector which is the first 4 bytes
  //     return abi.decode(revertData, (string)); // All that remains is the revert string
  // }
}
