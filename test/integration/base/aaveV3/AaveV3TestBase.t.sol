// SPDX-License-Identifier: MIT
// solhint-disable one-contract-per-file
pragma solidity 0.7.6;
pragma abicoder v2;

import {AaveV3TestSetup} from "test/integration/common/aaveV3/AaveV3TestSetup.t.sol";
import {BaseSetup} from "test/integration/utils/foundry/chains/BaseSetup.t.sol";
import {BaseConfig} from "test/integration/utils/foundry/config/BaseConfig.sol";

library AaveV3TestBaseSharedData {
  uint256 public constant FORK_BLOCK_NUMBER = 31387138;
}

contract AaveV3TestBase is AaveV3TestSetup, BaseSetup {
  constructor() AaveV3TestSetup(_createAaveV3TestConfig()) BaseSetup(AaveV3TestBaseSharedData.FORK_BLOCK_NUMBER) {}

  function setUp() public virtual override(AaveV3TestSetup, BaseSetup) {
    super.setUp();
  }

  function _createAaveV3TestConfig() internal pure returns (AaveV3TestSetup.AaveV3TestConfig memory config) {
    config.swapper = BaseConfig.SWAPPER;
    config.aaveV3Pool = BaseConfig.AAVE_V3_LENDING_POOL;
    config.uniV3Factory = BaseConfig.UNISWAP_V3_FACTORY;
    config.uniV3Router = BaseConfig.UNISWAP_V3_ROUTER;
    config.uniV2LikeRouters = _getV2Routers();
    config.token0ToLend = BaseConfig.WETH;
    config.token1ToLend = BaseConfig.cbBTC;
    config.tokenToBorrow = BaseConfig.USDC;
    config.token0AmountNormalized = 1;
    config.token1AmountNormalized = 1;
    config.tokenToBorrowAmountNormalized = 1000;
    config.token0Oracle = BaseConfig.WETH_CHAINLINK_ORACLE;
    config.token1Oracle = BaseConfig.cbBTC_CHAINLINK_ORACLE;
    config.tokenToBorrowOracle = BaseConfig.USDC_CHAINLINK_ORACLE;
    config.isL2 = true;
  }

  function _getV2Routers() internal pure returns (address[] memory v2Routers) {
    v2Routers = new address[](2);
    v2Routers[0] = BaseConfig.UNISWAP_V2_ROUTER;
    v2Routers[1] = BaseConfig.SUSHISWAP_ROUTER;
  }
}
