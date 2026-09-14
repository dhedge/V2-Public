// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {UniswapV3AssetGuardTestSetup} from "test/integration/common/uniswapV3/UniswapV3AssetGuardTestSetup.t.sol";
import {ArbitrumConfig} from "test/integration/utils/foundry/config/ArbitrumConfig.sol";
import {ArbitrumSetup} from "test/integration/utils/foundry/chains/ArbitrumSetup.t.sol";

/// @notice Runs the UniswapV3AssetGuard valuation suite against an Arbitrum fork. This suite enables
/// the position NFT on its vault from the start, so it needs its own vault and cannot share the one
/// the position guard suite builds.
contract UniswapV3AssetGuardTestArbitrum is UniswapV3AssetGuardTestSetup, ArbitrumSetup {
  constructor()
    UniswapV3AssetGuardTestSetup(
      UniswapV3AssetGuardTestSetup.TestParams({
        nftManager: ArbitrumConfig.UNISWAP_V3_NFT_MANAGER,
        uniswapV3Factory: ArbitrumConfig.UNISWAP_V3_FACTORY,
        swapRouter: ArbitrumConfig.UNISWAP_V3_ROUTER,
        supportedPairFee: 500, // WETH/USDC
        unsupportedTokenA: ArbitrumConfig.WBTC,
        unsupportedTokenAOracle: ArbitrumConfig.WBTC_CHAINLINK_ORACLE,
        unsupportedTokenB: ArbitrumConfig.LINK,
        bothUnsupportedFee: 3000, // WBTC/LINK
        oneUnsupportedFee: 500 // WBTC/WETH
      })
    )
    ArbitrumSetup(489036888)
  {}

  function setUp() public override(UniswapV3AssetGuardTestSetup, ArbitrumSetup) {
    super.setUp();
  }
}
