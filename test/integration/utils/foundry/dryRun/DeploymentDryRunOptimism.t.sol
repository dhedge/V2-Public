// SPDX-License-Identifier: MIT

pragma solidity >=0.7.6 <0.9.0;
pragma abicoder v2;

import {OptimismConfig} from "test/integration/utils/foundry/config/OptimismConfig.sol";
import {DeploymentDryRunTest} from "../DeploymentDryRunTest.t.sol";

abstract contract DeploymentDryRunOptimism is DeploymentDryRunTest {
  constructor(
    uint256 _forkBlockNumber,
    address[] memory _vaultsToTest
  )
    DeploymentDryRunTest(
      "optimism",
      _forkBlockNumber,
      _vaultsToTest,
      OptimismConfig.USDC,
      OptimismConfig.WETH,
      OptimismConfig.WBTC,
      OptimismConfig.POOL_FACTORY_PROD,
      OptimismConfig.NFT_TRACKER_PROD,
      OptimismConfig.SLIPPAGE_ACCUMULATOR_PROD,
      OptimismConfig.USD_PRICE_AGGREGATOR_PROD,
      OptimismConfig.PROXY_ADMIN
    )
  {}

  function setUp() public virtual override {
    super.setUp();
  }
}
