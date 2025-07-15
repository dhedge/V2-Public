// SPDX-License-Identifier: MIT
// solhint-disable one-contract-per-file
pragma solidity 0.7.6;
pragma abicoder v2;

import {AaveV3TestSetup} from "test/integration/common/aaveV3/AaveV3TestSetup.t.sol";
import {ArbitrumSetup} from "test/integration/utils/foundry/chains/ArbitrumSetup.t.sol";
import {ArbitrumConfig} from "test/integration/utils/foundry/config/ArbitrumConfig.sol";

library AaveV3TestArbitrumSharedData {
  uint256 public constant FORK_BLOCK_NUMBER = 353727847;
}

contract AaveV3TestArbitrum is AaveV3TestSetup, ArbitrumSetup {
  constructor()
    AaveV3TestSetup(_createAaveV3TestConfig())
    ArbitrumSetup(AaveV3TestArbitrumSharedData.FORK_BLOCK_NUMBER)
  {}

  function setUp() public virtual override(AaveV3TestSetup, ArbitrumSetup) {
    super.setUp();
  }

  function _createAaveV3TestConfig() internal pure returns (AaveV3TestSetup.AaveV3TestConfig memory config) {
    config.swapper = ArbitrumConfig.SWAPPER;
    config.aaveV3Pool = ArbitrumConfig.AAVE_V3_LENDING_POOL;
    config.uniV3Factory = ArbitrumConfig.UNISWAP_V3_FACTORY;
    config.uniV3Router = ArbitrumConfig.UNISWAP_V3_ROUTER;
    config.uniV2LikeRouters = _getV2Routers();
    config.token0ToLend = ArbitrumConfig.WETH;
    config.token1ToLend = ArbitrumConfig.DAI;
    config.tokenToBorrow = ArbitrumConfig.USDC;
    config.token0AmountNormalized = 1;
    config.token1AmountNormalized = 1000;
    config.tokenToBorrowAmountNormalized = 1000;
    config.token0Oracle = ArbitrumConfig.WETH_CHAINLINK_ORACLE;
    config.token1Oracle = ArbitrumConfig.DAI_CHAINLINK_ORACLE;
    config.tokenToBorrowOracle = ArbitrumConfig.USDC_CHAINLINK_ORACLE;
    config.isL2 = true;
  }

  function _getV2Routers() internal pure returns (address[] memory v2Routers) {
    v2Routers = new address[](2);
    v2Routers[0] = ArbitrumConfig.UNISWAP_V2_ROUTER;
    v2Routers[1] = ArbitrumConfig.SUSHISWAP_ROUTER;
  }
}
