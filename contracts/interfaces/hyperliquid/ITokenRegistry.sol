// SPDX-License-Identifier: MIT
pragma solidity >=0.7.6;

/// @dev Onchain token registry contract by Obsidian <https://github.com/hyperliquid-dev/hyper-evm-lib/blob/ee5e5e8593e9265fca35719e4efaa4fd3092123e/src/registry/TokenRegistry.sol>
interface ITokenRegistry {
  function getTokenIndex(address evmContract) external view returns (uint32 index);
}
