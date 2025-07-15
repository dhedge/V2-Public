// SPDX-License-Identifier: MIT

pragma solidity >=0.7.6;

library BaseConfig {
  uint256 public constant CHAIN_ID = 8453;

  address public constant PROXY_ADMIN = 0xD3113A115676EaF2c33bc40C336aa0595CbC8BDa;

  // dHEDGE Contracts
  address public constant POOL_FACTORY_PROD = 0x49Afe3abCf66CF09Fab86cb1139D8811C8afe56F;
  address public constant NFT_TRACKER_PROD = 0x08A664cA241DD50B1Dd5c9EBB97eCA33aC6f744E;
  address public constant SLIPPAGE_ACCUMULATOR_PROD = 0x75aD8f922a8C4386E4bf58C1648E22316ACb608f;
  address public constant USD_PRICE_AGGREGATOR_PROD = 0xE84e43DD22A608eFbc7f453f16c2bf398876417a;

  // Tokens
  address public constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
  address public constant WETH = 0x4200000000000000000000000000000000000006;
  address public constant WBTC = 0x0555E30da8f98308EdB960aa94C0Db47230d2B9c;
  address public constant DAI = 0x50c5725949A6F0c72E6C4a641F24049A917DB0Cb;
  address public constant cbBTC = 0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf;
  address public constant AERO = 0x940181a94A35A4569E4529A3CDfB74e38FD98631;

  // Oracles
  address public constant WETH_CHAINLINK_ORACLE = 0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70;
  address public constant USDC_CHAINLINK_ORACLE = 0x7e860098F58bBFC8648a4311b374B1D669a2bc6B;
  address public constant DAI_CHAINLINK_ORACLE = 0x591e79239a7d679378eC8c847e5038150364C78F;
  address public constant cbBTC_CHAINLINK_ORACLE = 0x07DA0E54543a844a80ABE69c8A12F22B3aA59f9D;

  // Toros Vaults
  address public constant BTCBULL3X = 0xCAF08BF08D0c87e2c74dd9EBEC9C776037bD7e8E;
  address public constant BTCBULL2X = 0x9e0501537723c71250307F5B1A8eE60e167D21C9;
  address public constant BTCBEAR1X = 0xd2f23773bF5e2d59F6bB925c2232F6e83f3f79e0;
  address public constant STETHBULL4X = 0xbA5F6A0D2AC21a3feC7a6C40FACd23407AA84663;
  address public constant STETHBULL3X = 0x15E2F06138aed58ca2A6AfB5A1333bBC5f728f80;
  address public constant STETHBULL2X = 0xA672e882aCBB96486393D43E0efdab5EBEbDDC1d;
  address public constant USDy = 0x1c980456751AE40315Ff73CaaC0843Be643321Be;
  address public constant ETHy = 0x53a4716a8f7DBC9543ebf9cd711952033cC64d43;
  address public constant USDmny = 0xeDE61eefa4850b459E3B09Fe6d8d371480D6fF00;

  // Auxiliary Contracts
  address public constant SWAPPER = 0x4F754e0F0924afD74980886b0B479Fa1D7C58D0D;
  address public constant AAVE_V3_LENDING_POOL = 0xA238Dd80C259a72e81d7e4664a9801593F98d1c5;
  address public constant UNISWAP_V3_FACTORY = 0x33128a8fC17869897dcE68Ed026d694621f6FDfD;
  address public constant UNISWAP_V3_ROUTER = 0x2626664c2603336E57B271c5C0b26F421741e481;
  address public constant SUSHISWAP_ROUTER = 0x6BDED42c6DA8FBf0d2bA55B2fa120C5e0c8D7891;
  address public constant UNISWAP_V2_ROUTER = 0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24;
  address public constant FLAT_MONEY_V1_DELAYED_ORDER = 0x6D857e9D24a7566bB72a3FB0847A3E0e4E1c2879;
}
