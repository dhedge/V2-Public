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

  /// @dev XAUT0's SECOND spot pair on HyperCore (index 209), quoted in USDT0 rather than USDC. It shares
  ///      its base token with `XAUT0_SPOT_INDEX`, so both pair ids resolve to the one XAUT0 Core balance.
  ///      HyperCore lists a token against several quote assets (mainnet: XAUT0 has 2 pairs, HYPE has 4),
  ///      and only the USDC-quoted one pays the vault in something its asset guards value.
  uint64 public constant XAUT0_ALT_SPOT_INDEX = 209;

  /// @dev Quote token of `XAUT0_ALT_SPOT_INDEX`. Not a dHEDGE asset, so nothing values it.
  uint64 public constant USDT0_TOKEN_INDEX = 268;

  // Auxiliary Contracts
  address public constant CORE_DEPOSIT_WALLET = 0x6B9E773128f453f5c2C60935Ee2DE2CBc5390A24;

  // Price Feed Addresses
  address public constant USDC_USD_PRICE_FEED = 0xA0Adc43ce7AfE3EE7d7eac3C994E178D0620223B;

  // Toros Vaults
  address public constant SP500BULL2X = 0xb360401bAeBE769aAEDF0212cb1ad6Fd8430A282;
  address public constant NVDABULL2X = 0xc722466CFc5bc7E7cc6e01A984621900376c5FfF;
  address public constant NVDABULL3X = 0x46F34e200Aa5a1a220B74E5d28665CC3CFCC739a;
  address public constant SP500BULL3X = 0xf1bBA105ee5Eb20129A943ab23ba1FaEaeF6b947;
  address public constant GOLDBULL3X = 0x6379297d251535BD4497C90d001787b53603CCA1;
  address public constant GOLDBULL2X = 0xEe55e2Df9a98ABC3F9a2f40FA96279742b1858bE;
  address public constant SLVBULL2X = 0x0AC8D6A003De1869d450216116736ae4B8b4F471;
  address public constant SLVBULL3X = 0xa8B3f14d88593e1B5460654cF8eCdaf6d47165A9;
  address public constant NDXBULL2X = 0xBc8124fa384247dF4E6f3EA2548bb78aB4bA9Fe4;
  address public constant NDXBULL3X = 0xBDb2a2641d8E291437e244c08e4433A13796E8dE;

  // Production vaults
  address public constant RSPSG = 0xCe508465b243216FcF372d3146fd62e8F7A7B8E2;
  address public constant KARMA = 0xA43Bd6b02190545c9E1cb518c53B0bFe4613df65;

  // Allowed Dex IDs
  function getAllowedDexIds() internal pure returns (uint256[] memory) {
    uint256[] memory ids = new uint256[](3);
    ids[0] = 1;
    ids[1] = 2;
    ids[2] = 3;

    return ids;
  }
}
