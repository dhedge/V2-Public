// SPDX-License-Identifier: MIT
// solhint-disable func-name-mixedcase
pragma solidity 0.7.6;

interface IAToken {
  /**
   * @notice Returns the address of the underlying asset of this aToken (E.g. WETH for aWETH)
   * @return The address of the underlying asset
   */
  function UNDERLYING_ASSET_ADDRESS() external view returns (address);
}
