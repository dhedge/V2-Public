// SPDX-License-Identifier: MIT

pragma solidity >=0.7.6 <0.9.0;
pragma abicoder v2;

import {BaseConfig} from "test/integration/utils/foundry/config/BaseConfig.sol";
import {DeploymentDryRunTest} from "../DeploymentDryRunTest.t.sol";

abstract contract DeploymentDryRunBase is DeploymentDryRunTest {
  constructor(
    uint256 _forkBlockNumber,
    address[] memory _vaultsToTest
  )
    DeploymentDryRunTest(
      "base",
      _forkBlockNumber,
      _vaultsToTest,
      BaseConfig.USDC,
      BaseConfig.WETH,
      BaseConfig.WBTC,
      BaseConfig.POOL_FACTORY_PROD,
      BaseConfig.NFT_TRACKER_PROD,
      BaseConfig.SLIPPAGE_ACCUMULATOR_PROD,
      BaseConfig.USD_PRICE_AGGREGATOR_PROD,
      BaseConfig.PROXY_ADMIN
    )
  {}

  function setUp() public virtual override {
    super.setUp();
  }
}
