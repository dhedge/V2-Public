// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.7.6;

/// @title The interface for the CL Factory
/// @notice The CL Factory facilitates creation of CL pools and control over the protocol fees
interface IVelodromeCLFactory {
  function getPool(address tokenA, address tokenB, int24 tickSpacing) external view returns (address pool);
  function tickSpacingToFee(int24 tickSpacing) external view returns (uint24 fee);
  function poolImplementation() external view returns (address);
}
