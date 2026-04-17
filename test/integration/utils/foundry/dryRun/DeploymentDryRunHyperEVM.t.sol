// SPDX-License-Identifier: MIT

pragma solidity >=0.7.6 <0.9.0;
pragma abicoder v2;

import {HyperEVMConfig} from "test/integration/utils/foundry/config/HyperEVMConfig.sol";
import {DeploymentDryRunTest} from "../DeploymentDryRunTest.t.sol";

abstract contract DeploymentDryRunHyperEVM is DeploymentDryRunTest {
  constructor(
    uint256 _forkBlockNumber,
    address[] memory _vaultsToTest
  )
    DeploymentDryRunTest(
      "hyperevm",
      _forkBlockNumber,
      _vaultsToTest,
      HyperEVMConfig.USDC_TOKEN_ADDRESS,
      HyperEVMConfig.WHYPE_TOKEN_ADDRESS,
      address(0),
      HyperEVMConfig.POOL_FACTORY_PROD,
      address(0),
      HyperEVMConfig.SLIPPAGE_ACCUMULATOR_PROD,
      HyperEVMConfig.USD_PRICE_AGGREGATOR_PROD,
      HyperEVMConfig.PROXY_ADMIN
    )
  {}

  function setUp() public virtual override {
    super.setUp();
  }
}
