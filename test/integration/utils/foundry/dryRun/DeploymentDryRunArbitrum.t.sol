// SPDX-License-Identifier: MIT

pragma solidity >=0.7.6 <0.9.0;
pragma abicoder v2;

import {ArbitrumConfig} from "test/integration/utils/foundry/config/ArbitrumConfig.sol";
import {DeploymentDryRunTest} from "../DeploymentDryRunTest.t.sol";

abstract contract DeploymentDryRunArbitrum is DeploymentDryRunTest {
  constructor(
    uint256 _forkBlockNumber,
    address[] memory _vaultsToTest
  )
    DeploymentDryRunTest(
      "arbitrum",
      _forkBlockNumber,
      _vaultsToTest,
      ArbitrumConfig.USDC,
      ArbitrumConfig.WETH,
      ArbitrumConfig.WBTC,
      ArbitrumConfig.POOL_FACTORY_PROD,
      ArbitrumConfig.NFT_TRACKER_PROD,
      ArbitrumConfig.SLIPPAGE_ACCUMULATOR_PROD,
      ArbitrumConfig.USD_PRICE_AGGREGATOR_PROD,
      ArbitrumConfig.PROXY_ADMIN
    )
  {}

  function setUp() public virtual override {
    super.setUp();
  }
}
