// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {AaveV3TestSetup} from "test/integration/common/aaveV3/AaveV3TestSetup.t.sol";
import {EthereumSetup} from "test/integration/utils/foundry/chains/EthereumSetup.t.sol";
import {EthereumConfig} from "test/integration/utils/foundry/config/EthereumConfig.sol";

contract AaveV3LendsPTsUSDeAndSUSDeTest is AaveV3TestSetup, EthereumSetup {
  uint256 private testForkBlockNumber = 23617794;

  constructor() AaveV3TestSetup(_createAaveV3TestConfig()) EthereumSetup(testForkBlockNumber) {}

  function _createAaveV3TestConfig() internal pure returns (AaveV3TestSetup.AaveV3TestConfig memory config) {
    config.swapper = EthereumConfig.SWAPPER;
    config.aaveV3Pool = EthereumConfig.AAVE_V3_LENDING_POOL;
    config.uniV3Factory = EthereumConfig.UNISWAP_V3_FACTORY;
    config.uniV3Router = EthereumConfig.UNISWAP_V3_ROUTER;
    config.uniV2LikeRouters = new address[](0);
    config.token0ToLend = EthereumConfig.PT_sUSDe_NOV_2025;
    config.token1ToLend = EthereumConfig.sUSDe;
    config.tokenToBorrow = EthereumConfig.USDT;
    config.token0AmountNormalized = 10000;
    config.token1AmountNormalized = 1000;
    config.tokenToBorrowAmountNormalized = 8000;
    config.token0Oracle = 0xB4503d626C2Cb73cf9D027499Cefc47b5A0C6a2E;
    config.token1Oracle = 0xD511fbF9618Fa76Dd73796Eb9c3E500030F36A7D;
    config.tokenToBorrowOracle = EthereumConfig.USDT_CHAINLINK_ORACLE;
    config.pendleYieldContractFactory = EthereumConfig.PENDLE_YIELD_CONTRACT_FACTORY;
    config.pendleStaticRouter = EthereumConfig.PENDLE_STATIC_ROUTER;
    config.token0ToLendPendleMarket = EthereumConfig.PENDLE_MARKET_sUSDe_NOV_2025;
    config.token0ToLendUnderlying = EthereumConfig.sUSDe;
    config.token0ToLendUnderlyingOracle = 0xD511fbF9618Fa76Dd73796Eb9c3E500030F36A7D;
    config.useEMode = 24; // PT sUSDe Stablecoins NOV 2025 eMode ID
  }

  function setUp() public virtual override(AaveV3TestSetup, EthereumSetup) {
    super.setUp();
  }
}
