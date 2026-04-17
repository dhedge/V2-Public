// SPDX-License-Identifier: MIT

pragma solidity >=0.7.6 <0.9.0;
pragma abicoder v2;

import {PlasmaConfig} from "test/integration/utils/foundry/config/PlasmaConfig.sol";
import {DeploymentDryRunTest} from "../DeploymentDryRunTest.t.sol";

abstract contract DeploymentDryRunPlasma is DeploymentDryRunTest {
  constructor(
    uint256 _forkBlockNumber,
    address[] memory _vaultsToTest
  )
    DeploymentDryRunTest(
      "plasma",
      _forkBlockNumber,
      _vaultsToTest,
      PlasmaConfig.USDT,
      PlasmaConfig.WETH,
      address(0),
      PlasmaConfig.POOL_FACTORY_PROD,
      address(0),
      PlasmaConfig.SLIPPAGE_ACCUMULATOR_PROD,
      PlasmaConfig.USD_PRICE_AGGREGATOR_PROD,
      PlasmaConfig.PROXY_ADMIN
    )
  {}

  function setUp() public virtual override {
    super.setUp();
  }
}
