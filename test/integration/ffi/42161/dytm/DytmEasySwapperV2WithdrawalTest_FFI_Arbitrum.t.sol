// SPDX-License-Identifier: MIT
// solhint-disable one-contract-per-file
pragma solidity 0.7.6;
pragma abicoder v2;

import {DytmEasySwapperV2WithdrawalTestSetup} from "test/integration/common/dytm/DytmEasySwapperV2WithdrawalTestSetup.t.sol";
import {DytmDelegationCallTestSetup} from "test/integration/common/dytm/DytmDelegationCallTestSetup.t.sol";
import {ArbitrumSetup} from "test/integration/utils/foundry/chains/ArbitrumSetup.t.sol";
import {ArbitrumConfig} from "test/integration/utils/foundry/config/ArbitrumConfig.sol";

library DytmEasySwapperV2WithdrawalTestArbitrumSharedData {
  uint256 public constant FORK_BLOCK_NUMBER = 437906125;

  address public constant DYTM_OFFICE = 0x0fF1CEE337d7af25eEF4c1a7A2CaF83f98d80001;
  address public constant DYTM_PERIPHERY = 0x1FBe7Bb394BE505C08e9ee419Dd166c71004e51B;
  address public constant DYTM_ACCOUNT_SPLITTER_AND_MERGER = 0xCa52E5c2FBa054059Bc0F25AcFEB365e683C9c31;
  address public constant DYTM_MARKET_CONFIG = 0x0666Dd5ca7BA1A7716CF98be6A1F6Fb4349b171f;
  uint256 public constant MAX_DYTM_MARKETS = 1;

  // Using DYTM Testing dHedge pool as collateral
  address public constant COLLATERAL_ASSET = 0xA6711f8a184E352c5A0714a48912cD33ca4a16A0; // DYTM Testing
  bool public constant IS_COLLATERAL_DHEDGE_POOL_TOKEN = true;

  address public constant MARKET_CREATOR = 0x255bfAfC9Dcb926e71e172B6AA8d912A158A32B9; // DYTM Market Creator
  uint88 public constant DYTM_MARKET_ID = 1;

  // Odos V3 Router on Arbitrum
  address public constant ODOS_ROUTER = 0x0D05a7D3448512B78fa8A9e46c4872C88C4a0D05;
}

contract DytmEasySwapperV2WithdrawalTestFFIArbitrum is DytmEasySwapperV2WithdrawalTestSetup, ArbitrumSetup {
  constructor()
    DytmDelegationCallTestSetup(_createDytmDelegationCallTestConfig())
    ArbitrumSetup(DytmEasySwapperV2WithdrawalTestArbitrumSharedData.FORK_BLOCK_NUMBER)
  {}

  function setUp() public virtual override(DytmEasySwapperV2WithdrawalTestSetup, ArbitrumSetup) {
    super.setUp();
  }

  function _createDytmDelegationCallTestConfig()
    internal
    pure
    returns (DytmDelegationCallTestSetup.DytmDelegationCallTestConfig memory config)
  {
    config.dhedgePoolFactory = ArbitrumConfig.POOL_FACTORY_PROD;
    config.nftTracker = ArbitrumConfig.NFT_TRACKER_PROD;

    // Assets configuration
    config.borrowAsset = ArbitrumConfig.USDC; // Native USDC
    config.swapToAsset = ArbitrumConfig.WETH; // We'll swap borrowed USDC to WETH
    config.collateralAsset = DytmEasySwapperV2WithdrawalTestArbitrumSharedData.COLLATERAL_ASSET; // DYTM Testing pool

    // Amounts
    config.collateralAmountNormalized = 100; // 100 DYTMT pool tokens
    config.borrowAmountNormalized = 40; // 40 USDC

    // Oracles
    config.collateralOracle = address(0); // Will use DHedgePoolAggregator
    config.borrowOracle = ArbitrumConfig.USDC_CHAINLINK_ORACLE;
    config.swapToAssetOracle = ArbitrumConfig.WETH_CHAINLINK_ORACLE;

    // DYTM configuration
    config.dytmOffice = DytmEasySwapperV2WithdrawalTestArbitrumSharedData.DYTM_OFFICE;
    config.dytmPeriphery = DytmEasySwapperV2WithdrawalTestArbitrumSharedData.DYTM_PERIPHERY;
    config.dytmMarketConfig = DytmEasySwapperV2WithdrawalTestArbitrumSharedData.DYTM_MARKET_CONFIG;
    config.accountSplitterAndMerger = DytmEasySwapperV2WithdrawalTestArbitrumSharedData
      .DYTM_ACCOUNT_SPLITTER_AND_MERGER;
    config.maxDytmMarkets = DytmEasySwapperV2WithdrawalTestArbitrumSharedData.MAX_DYTM_MARKETS;
    config.isCollateralDhedgePoolToken = DytmEasySwapperV2WithdrawalTestArbitrumSharedData
      .IS_COLLATERAL_DHEDGE_POOL_TOKEN;
    config.marketCreator = DytmEasySwapperV2WithdrawalTestArbitrumSharedData.MARKET_CREATOR;
    config.dytmMarketId = DytmEasySwapperV2WithdrawalTestArbitrumSharedData.DYTM_MARKET_ID;

    // Odos configuration
    config.odosRouter = DytmEasySwapperV2WithdrawalTestArbitrumSharedData.ODOS_ROUTER;
    config.chainId = ArbitrumConfig.CHAIN_ID;

    // Slippage Accumulator
    config.slippageAccumulator = ArbitrumConfig.SLIPPAGE_ACCUMULATOR_PROD;
    config.easySwapperV2Instance = ArbitrumConfig.EASY_SWAPPER_V2_PROD;
    config.proxyAdmin = ArbitrumConfig.PROXY_ADMIN;

    // Pendle PT Configuration (PT-wstETH-25JUN2026)
    config.pendlePT = 0x71fBF40651E9D4278a74586AfC99F307f369Ce9A;
    config.pendleMarket = 0xf78452e0f5C0B95fc5dC8353B8CD1e06E53fa25B;
    config.pendlePTUnderlying = 0x5979D7b546E38E414F7E9822514be443A4800529; // wstETH
    config.pendleStaticRouter = 0xAdB09F65bd90d19e3148D9ccb693F3161C6DB3E8;
  }
}
