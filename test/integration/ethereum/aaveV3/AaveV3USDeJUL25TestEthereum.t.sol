// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {AaveV3TestSetup} from "test/integration/common/aaveV3/AaveV3TestSetup.t.sol";
import {EthereumSetup} from "test/integration/utils/foundry/chains/EthereumSetup.t.sol";
import {EthereumConfig} from "test/integration/utils/foundry/config/EthereumConfig.sol";

contract AaveV3USDeJUL25TestEthereum is AaveV3TestSetup, EthereumSetup {
  uint256 private testForkBlockNumber = 22732376;

  constructor() AaveV3TestSetup(_createAaveV3TestConfig()) EthereumSetup(testForkBlockNumber) {}

  function _createAaveV3TestConfig() internal pure returns (AaveV3TestSetup.AaveV3TestConfig memory config) {
    config.swapper = EthereumConfig.SWAPPER;
    config.aaveV3Pool = EthereumConfig.AAVE_V3_LENDING_POOL;
    config.uniV3Factory = EthereumConfig.UNISWAP_V3_FACTORY;
    config.uniV3Router = EthereumConfig.UNISWAP_V3_ROUTER;
    config.uniV2LikeRouters = new address[](0);
    config.token0ToLend = EthereumConfig.PT_USDe_JUL_2025;
    config.token1ToLend = EthereumConfig.USDT;
    config.tokenToBorrow = EthereumConfig.USDC;
    config.token0AmountNormalized = 10000;
    config.token1AmountNormalized = 1000;
    config.tokenToBorrowAmountNormalized = 8000;
    config.token0Oracle = EthereumConfig.PT_USDe_JUL_2025_PRICE_AGGREGATOR;
    config.token1Oracle = EthereumConfig.USDT_CHAINLINK_ORACLE;
    config.tokenToBorrowOracle = EthereumConfig.USDC_CHAINLINK_ORACLE;
    config.pendleYieldContractFactory = EthereumConfig.PENDLE_YIELD_CONTRACT_FACTORY;
    config.pendleStaticRouter = EthereumConfig.PENDLE_STATIC_ROUTER;
    config.token0ToLendPendleMarket = EthereumConfig.PENDLE_MARKET_USDe_JUL_2025;
    config.token0ToLendUnderlying = EthereumConfig.USDe;
    config.token0ToLendUnderlyingOracle = EthereumConfig.USDe_CHAINLINK_ORACLE;
    config.useEMode = 10; // PT USDe Stablecoins JUL 2025 eMode ID
  }

  function setUp() public virtual override(AaveV3TestSetup, EthereumSetup) {
    super.setUp();
  }
}
