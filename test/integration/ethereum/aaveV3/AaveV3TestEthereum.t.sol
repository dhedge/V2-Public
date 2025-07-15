// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {AaveV3TestSetup} from "test/integration/common/aaveV3/AaveV3TestSetup.t.sol";
import {EthereumSetup} from "test/integration/utils/foundry/chains/EthereumSetup.t.sol";
import {EthereumConfig} from "test/integration/utils/foundry/config/EthereumConfig.sol";

contract AaveV3TestEthereum is AaveV3TestSetup, EthereumSetup {
  uint256 private testForkBlockNumber = 22669363;

  constructor() AaveV3TestSetup(_createAaveV3TestConfig()) EthereumSetup(testForkBlockNumber) {}

  function _createAaveV3TestConfig() internal pure returns (AaveV3TestSetup.AaveV3TestConfig memory config) {
    config.swapper = EthereumConfig.SWAPPER;
    config.aaveV3Pool = EthereumConfig.AAVE_V3_LENDING_POOL;
    config.uniV3Factory = EthereumConfig.UNISWAP_V3_FACTORY;
    config.uniV3Router = EthereumConfig.UNISWAP_V3_ROUTER;
    config.uniV2LikeRouters = _getV2Routers();
    config.token0ToLend = EthereumConfig.WETH;
    config.token1ToLend = EthereumConfig.USDT;
    config.tokenToBorrow = EthereumConfig.USDC;
    config.token0AmountNormalized = 1;
    config.token1AmountNormalized = 1000;
    config.tokenToBorrowAmountNormalized = 1000;
    config.token0Oracle = EthereumConfig.WETH_CHAINLINK_ORACLE;
    config.token1Oracle = EthereumConfig.USDT_CHAINLINK_ORACLE;
    config.tokenToBorrowOracle = EthereumConfig.USDC_CHAINLINK_ORACLE;
  }

  function setUp() public virtual override(AaveV3TestSetup, EthereumSetup) {
    super.setUp();
  }

  function _getV2Routers() internal pure returns (address[] memory v2Routers) {
    v2Routers = new address[](2);
    v2Routers[0] = EthereumConfig.UNISWAP_V2_ROUTER;
    v2Routers[1] = EthereumConfig.SUSHISWAP_ROUTER;
  }
}
