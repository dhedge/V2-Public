// SPDX-License-Identifier: MIT
// solhint-disable one-contract-per-file
pragma solidity 0.7.6;
pragma abicoder v2;

import {AaveV3TestSetup} from "test/integration/common/aaveV3/AaveV3TestSetup.t.sol";
import {OptimismSetup} from "test/integration/utils/foundry/chains/OptimismSetup.t.sol";
import {OptimismConfig} from "test/integration/utils/foundry/config/OptimismConfig.sol";
import {ForkBlocks} from "test/integration/utils/foundry/config/ForkBlocks.sol";

contract AaveV3TestOptimism is AaveV3TestSetup, OptimismSetup {
  constructor() AaveV3TestSetup(_createAaveV3TestConfig()) OptimismSetup(ForkBlocks.OPTIMISM) {}

  function setUp() public virtual override(AaveV3TestSetup, OptimismSetup) {
    super.setUp();
  }

  function _createAaveV3TestConfig() internal pure returns (AaveV3TestSetup.AaveV3TestConfig memory config) {
    config.swapper = OptimismConfig.SWAPPER;
    config.aaveV3Pool = OptimismConfig.AAVE_V3_LENDING_POOL;
    config.uniV3Factory = OptimismConfig.UNISWAP_V3_FACTORY;
    config.uniV3Router = OptimismConfig.UNISWAP_V3_ROUTER;
    config.uniV2LikeRouters = _getV2Routers();
    config.token0ToLend = OptimismConfig.WETH;
    // Aave froze the DAI reserve on this chain (low-adoption deprecation), so the second lend asset is WBTC.
    config.token1ToLend = OptimismConfig.WBTC;
    config.tokenToBorrow = OptimismConfig.USDC;
    config.token0AmountNormalized = 1;
    config.token1AmountNormalized = 1;
    config.tokenToBorrowAmountNormalized = 1000;
    config.token0Oracle = OptimismConfig.WETH_CHAINLINK_ORACLE;
    config.token1Oracle = OptimismConfig.WBTC_CHAINLINK_ORACLE;
    config.tokenToBorrowOracle = OptimismConfig.USDC_CHAINLINK_ORACLE;
    config.isL2 = true;
  }

  function _getV2Routers() internal pure returns (address[] memory v2Routers) {
    v2Routers = new address[](1);
    v2Routers[0] = OptimismConfig.UNISWAP_V2_ROUTER;
  }
}
