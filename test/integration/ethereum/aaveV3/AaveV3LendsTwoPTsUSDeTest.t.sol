// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {AaveV3TestSetup} from "test/integration/common/aaveV3/AaveV3TestSetup.t.sol";
import {EthereumSetup} from "test/integration/utils/foundry/chains/EthereumSetup.t.sol";
import {EthereumConfig} from "test/integration/utils/foundry/config/EthereumConfig.sol";

contract AaveV3LendsTwoPTsUSDeTest is AaveV3TestSetup, EthereumSetup {
  uint256 private testForkBlockNumber = 23296986;

  constructor() AaveV3TestSetup(_createAaveV3TestConfig()) EthereumSetup(testForkBlockNumber) {}

  function _createAaveV3TestConfig() internal pure returns (AaveV3TestSetup.AaveV3TestConfig memory config) {
    config.swapper = EthereumConfig.SWAPPER;
    config.aaveV3Pool = EthereumConfig.AAVE_V3_LENDING_POOL;
    config.uniV3Factory = EthereumConfig.UNISWAP_V3_FACTORY;
    config.uniV3Router = EthereumConfig.UNISWAP_V3_ROUTER;
    config.uniV2LikeRouters = new address[](0);
    config.token0ToLend = EthereumConfig.PT_sUSDe_NOV_2025;
    config.token1ToLend = EthereumConfig.PT_sUSDe_SEP_2025;
    config.tokenToBorrow = EthereumConfig.USDT;
    config.token0AmountNormalized = 10000;
    config.token1AmountNormalized = 1000;
    config.tokenToBorrowAmountNormalized = 8000;
    config.token0Oracle = EthereumConfig.PT_sUSDe_NOV_2025_PRICE_AGGREGATOR;
    config.token1Oracle = 0x6677c3745bD5bF8863e4a7e23F64442971c7BF79;
    config.tokenToBorrowOracle = EthereumConfig.USDT_CHAINLINK_ORACLE;
    config.pendleYieldContractFactory = EthereumConfig.PENDLE_YIELD_CONTRACT_FACTORY;
    config.pendleStaticRouter = EthereumConfig.PENDLE_STATIC_ROUTER;
    config.token0ToLendPendleMarket = EthereumConfig.PENDLE_MARKET_sUSDe_NOV_2025;
    config.token1ToLendPendleMarket = EthereumConfig.PENDLE_MARKET_sUSDe_SEP_2025;
    config.token0ToLendUnderlying = EthereumConfig.sUSDe;
    config.token0ToLendUnderlyingOracle = 0x13192c31825dc609856c1Da51041A956B45068d9;
    config.useEMode = 24; // PT sUSDe Stablecoins NOV 2025 eMode ID
  }

  function setUp() public virtual override(AaveV3TestSetup, EthereumSetup) {
    super.setUp();
  }
}
