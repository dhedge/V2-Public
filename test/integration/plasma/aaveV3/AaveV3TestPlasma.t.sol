// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {AaveV3TestSetup} from "test/integration/common/aaveV3/AaveV3TestSetup.t.sol";
import {PlasmaSetup} from "test/integration/utils/foundry/chains/PlasmaSetup.t.sol";
import {PlasmaConfig} from "test/integration/utils/foundry/config/PlasmaConfig.sol";

contract AaveV3TestPlasma is AaveV3TestSetup, PlasmaSetup {
  uint256 private testForkBlockNumber = 3937486;

  constructor() AaveV3TestSetup(_createAaveV3TestConfig()) PlasmaSetup(testForkBlockNumber) {}

  function _createAaveV3TestConfig() internal pure returns (AaveV3TestSetup.AaveV3TestConfig memory config) {
    config.swapper = PlasmaConfig.SWAPPER;
    config.aaveV3Pool = PlasmaConfig.AAVE_V3_LENDING_POOL;
    config.uniV3Factory = address(0);
    config.uniV3Router = address(0);
    config.uniV2LikeRouters = _getV2Routers();
    config.token0ToLend = PlasmaConfig.WETH;
    config.token1ToLend = PlasmaConfig.USDT;
    config.tokenToBorrow = PlasmaConfig.USDe;
    config.token0AmountNormalized = 1;
    config.token1AmountNormalized = 1000;
    config.tokenToBorrowAmountNormalized = 1000;
    config.token0Oracle = PlasmaConfig.WETH_CHAINLINK_ORACLE;
    config.token1Oracle = PlasmaConfig.USDT_CHAINLINK_ORACLE;
    config.tokenToBorrowOracle = PlasmaConfig.USDe_CHAINLINK_ORACLE;
  }

  function setUp() public virtual override(AaveV3TestSetup, PlasmaSetup) {
    super.setUp();
  }

  function _getV2Routers() internal pure returns (address[] memory v2Routers) {
    v2Routers = new address[](0);
  }
}
