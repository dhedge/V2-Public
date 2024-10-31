// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

library AddressArrayLib {
  // Function to check if an address is in the array
  function contains(address[] memory array, address element) internal pure returns (bool) {
    for (uint256 i = 0; i < array.length; i++) {
      if (array[i] == element) {
        return true;
      }
    }
    return false;
  }
}
