// SPDX-License-Identifier: MIT

pragma solidity >=0.7.6;

/// @title HyperEVM configuration for Foundry tests
/// @notice Contains addresses and constants for HyperEVM chain integration testing
library HyperEVMConfig {
  uint256 public constant CHAIN_ID = 999; // HyperEVM Mainnet

  address public constant PROXY_ADMIN = 0xD2d91d3cA66E15598181562654D4727355a31E4b;

  // dHEDGE Contracts
  address public constant POOL_FACTORY_PROD = 0x615037C2Df6FA97634c5aD2d8144708b9dd3B176;
  address public constant USD_PRICE_AGGREGATOR_PROD = 0x14EB3ab377265cfaEA63386355A556C2e044A9C2;
  address public constant SLIPPAGE_ACCUMULATOR_PROD = 0x7E3d6d84046783721260ae8E5Fa7D29Bd227EE6A;

  // Hyperliquid System Addresses
  address public constant CORE_WRITER = 0x3333333333333333333333333333333333333333;

  // Tokens
  address public constant USDC_TOKEN_ADDRESS = 0xb88339CB7199b77E23DB6E890353E22632Ba630f;
  address public constant WHYPE_TOKEN_ADDRESS = 0x5555555555555555555555555555555555555555;
  address public constant XAUT0_TOKEN_ADDRESS = 0xf4D9235269a96aaDaFc9aDAe454a0618eBE37949;
  address public constant USDC_SYSTEM_ADDRESS = 0x2000000000000000000000000000000000000000;
  address public constant HYPE_SYSTEM_ADDRESS = 0x2222222222222222222222222222222222222222;
  address public constant XAUT0_SYSTEM_ADDRESS = 0x2000000000000000000000000000000000000129;
  uint32 public constant XAUT0_TOKEN_INDEX = 297;
  uint64 public constant XAUT0_SPOT_INDEX = 182;

  // Auxiliary Contracts
  address public constant CORE_DEPOSIT_WALLET = 0x6B9E773128f453f5c2C60935Ee2DE2CBc5390A24;

  // Price Feed Addresses
  address public constant USDC_USD_PRICE_FEED = 0xA0Adc43ce7AfE3EE7d7eac3C994E178D0620223B;

  // Allowed Dex IDs
  function getAllowedDexIds() internal pure returns (uint256[] memory) {
    uint256[] memory ids = new uint256[](3);
    ids[0] = 1;
    ids[1] = 2;
    ids[2] = 3;

    return ids;
  }
}
