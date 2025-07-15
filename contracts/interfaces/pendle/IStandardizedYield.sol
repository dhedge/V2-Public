// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.7.6;

interface IStandardizedYield {
  /**
   * @notice returns the address of the underlying yield token
   */
  function yieldToken() external view returns (address);
}
