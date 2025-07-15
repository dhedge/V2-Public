// SPDX-License-Identifier: MIT
// solhint-disable one-contract-per-file
pragma solidity 0.7.6;
pragma abicoder v2;

import {AaveV3TestSetup} from "test/integration/common/aaveV3/AaveV3TestSetup.t.sol";
import {PolygonSetup} from "test/integration/utils/foundry/chains/PolygonSetup.t.sol";
import {PolygonConfig} from "test/integration/utils/foundry/config/PolygonConfig.sol";

library AaveV3TestPolygonSharedData {
  uint256 public constant FORK_BLOCK_NUMBER = 72950511;
}

contract AaveV3TestPolygon is AaveV3TestSetup, PolygonSetup {
  constructor()
    AaveV3TestSetup(_createAaveV3TestConfig())
    PolygonSetup(AaveV3TestPolygonSharedData.FORK_BLOCK_NUMBER)
  {}

  function setUp() public virtual override(AaveV3TestSetup, PolygonSetup) {
    super.setUp();
  }

  function _createAaveV3TestConfig() internal pure returns (AaveV3TestSetup.AaveV3TestConfig memory config) {
    config.swapper = PolygonConfig.SWAPPER;
    config.aaveV3Pool = PolygonConfig.AAVE_V3_LENDING_POOL;
    config.uniV3Factory = PolygonConfig.UNISWAP_V3_FACTORY;
    config.uniV3Router = PolygonConfig.UNISWAP_V3_ROUTER;
    config.uniV2LikeRouters = _getV2Routers();
    config.token0ToLend = PolygonConfig.WETH;
    config.token1ToLend = PolygonConfig.DAI;
    config.tokenToBorrow = PolygonConfig.USDC;
    config.token0AmountNormalized = 1;
    config.token1AmountNormalized = 1000;
    config.tokenToBorrowAmountNormalized = 1000;
    config.token0Oracle = PolygonConfig.WETH_CHAINLINK_ORACLE;
    config.token1Oracle = PolygonConfig.DAI_CHAINLINK_ORACLE;
    config.tokenToBorrowOracle = PolygonConfig.USDC_CHAINLINK_ORACLE;
  }

  function _getV2Routers() internal pure returns (address[] memory v2Routers) {
    v2Routers = new address[](3);
    v2Routers[0] = PolygonConfig.UNISWAP_V2_ROUTER;
    v2Routers[1] = PolygonConfig.QUICKSWAP_V2_ROUTER;
    v2Routers[2] = PolygonConfig.SUSHISWAP_ROUTER;
  }
}
