// SPDX-License-Identifier: MIT

pragma solidity >=0.7.6 <0.9.0;
pragma abicoder v2;

import {EthereumConfig} from "test/integration/utils/foundry/config/EthereumConfig.sol";
import {DeploymentDryRunTest} from "../DeploymentDryRunTest.t.sol";

abstract contract DeploymentDryRunEthereum is DeploymentDryRunTest {
  constructor(
    uint256 _forkBlockNumber,
    address[] memory _vaultsToTest
  )
    DeploymentDryRunTest(
      "ethereum",
      _forkBlockNumber,
      _vaultsToTest,
      EthereumConfig.USDC,
      EthereumConfig.WETH,
      EthereumConfig.WBTC,
      EthereumConfig.POOL_FACTORY_PROD,
      address(0),
      EthereumConfig.SLIPPAGE_ACCUMULATOR_PROD,
      EthereumConfig.USD_PRICE_AGGREGATOR_PROD,
      EthereumConfig.PROXY_ADMIN
    )
  {}

  function setUp() public virtual override {
    super.setUp();
  }
}
