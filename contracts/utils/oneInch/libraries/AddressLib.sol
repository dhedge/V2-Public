// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

/**
 * @dev Library for working with addresses encoded as uint256 values, which can include flags in the highest bits.
 *      Taken from 1inch AggregationRouterV6 contract, rest of the library can be found there.
 */
library AddressLib {
  uint256 private constant _LOW_160_BIT_MASK = (1 << 160) - 1;

  /**
   * @notice Returns the address representation of a uint256.
   * @param a The uint256 value to convert to an address.
   * @return The address representation of the provided uint256 value.
   */
  function get(uint256 a) internal pure returns (address) {
    return address(uint160(a & _LOW_160_BIT_MASK));
  }

  /**
   * @notice Checks if a given flag is set for the provided address.
   * @param a The address to check for the flag.
   * @param flag The flag to check for in the provided address.
   * @return True if the provided flag is set in the address, false otherwise.
   */
  function getFlag(uint256 a, uint256 flag) internal pure returns (bool) {
    return (a & flag) != 0;
  }
}
