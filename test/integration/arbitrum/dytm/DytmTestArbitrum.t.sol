// SPDX-License-Identifier: MIT
// solhint-disable one-contract-per-file
pragma solidity 0.7.6;
pragma abicoder v2;

import {DytmTestSetup} from "test/integration/common/dytm/DytmTestSetup.t.sol";
import {ArbitrumSetup} from "test/integration/utils/foundry/chains/ArbitrumSetup.t.sol";
import {ArbitrumConfig} from "test/integration/utils/foundry/config/ArbitrumConfig.sol";

library DytmTestArbitrumSharedData {
  uint256 public constant FORK_BLOCK_NUMBER = 437520103;

  address public constant DYTM_OFFICE = 0x0fF1CEE337d7af25eEF4c1a7A2CaF83f98d80001;
  address public constant DYTM_PERIPHERY = 0x1FBe7Bb394BE505C08e9ee419Dd166c71004e51B;
  address public constant DYTM_ACCOUNT_SPLITTER_AND_MERGER = 0xCa52E5c2FBa054059Bc0F25AcFEB365e683C9c31;
  address public constant DYTM_MARKET_CONFIG = 0x0666Dd5ca7BA1A7716CF98be6A1F6Fb4349b171f;
  uint256 public constant MAX_DYTM_MARKETS = 1;
  address public constant COLLATERAL_ASSET = 0xA6711f8a184E352c5A0714a48912cD33ca4a16A0; // DYTM Testing, https://dhedge.org/vault/0xA6711f8a184E352c5A0714a48912cD33ca4a16A0
  bool public constant IS_COLLATERAL_DHEDGE_POOL_TOKEN = true;
  address public constant MARKET_CREATOR = 0x255bfAfC9Dcb926e71e172B6AA8d912A158A32B9; // DYTM Market Creator
  uint88 public constant DYTM_MARKET_ID = 1;
}

contract DytmTestArbitrum is DytmTestSetup, ArbitrumSetup {
  constructor() DytmTestSetup(_createDytmTestConfig()) ArbitrumSetup(DytmTestArbitrumSharedData.FORK_BLOCK_NUMBER) {}

  function setUp() public virtual override(DytmTestSetup, ArbitrumSetup) {
    super.setUp();
  }

  function _createDytmTestConfig() internal pure returns (DytmTestSetup.DytmTestConfig memory config) {
    config.dhedgePoolFactory = ArbitrumConfig.POOL_FACTORY_PROD;
    config.nftTracker = ArbitrumConfig.NFT_TRACKER_PROD;

    config.borrowAsset = ArbitrumConfig.USDC;
    config.collateralAmountNormalized = 100; // 100 DYTMT
    config.borrowAmountNormalized = 40; // 40 USDC
    config.collateralOracle = address(0);
    config.borrowOracle = ArbitrumConfig.USDC_CHAINLINK_ORACLE;

    config.dytmOffice = DytmTestArbitrumSharedData.DYTM_OFFICE;
    config.dytmPeriphery = DytmTestArbitrumSharedData.DYTM_PERIPHERY;
    config.dytmMarketConfig = DytmTestArbitrumSharedData.DYTM_MARKET_CONFIG;
    config.accountSplitterAndMerger = DytmTestArbitrumSharedData.DYTM_ACCOUNT_SPLITTER_AND_MERGER;
    config.collateralAsset = DytmTestArbitrumSharedData.COLLATERAL_ASSET;
    config.maxDytmMarkets = DytmTestArbitrumSharedData.MAX_DYTM_MARKETS;
    config.isCollateralDhedgePoolToken = DytmTestArbitrumSharedData.IS_COLLATERAL_DHEDGE_POOL_TOKEN;
    config.marketCreator = DytmTestArbitrumSharedData.MARKET_CREATOR;
    config.dytmMarketId = DytmTestArbitrumSharedData.DYTM_MARKET_ID;
  }
}
