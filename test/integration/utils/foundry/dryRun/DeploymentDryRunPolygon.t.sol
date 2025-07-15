// SPDX-License-Identifier: MIT

pragma solidity >=0.7.6 <0.9.0;
pragma abicoder v2;

import {PolygonConfig} from "test/integration/utils/foundry/config/PolygonConfig.sol";
import {DeploymentDryRunTest} from "../DeploymentDryRunTest.t.sol";

abstract contract DeploymentDryRunPolygon is DeploymentDryRunTest {
  constructor(
    uint256 _forkBlockNumber,
    address[] memory _vaultsToTest
  )
    DeploymentDryRunTest(
      "polygon",
      _forkBlockNumber,
      _vaultsToTest,
      PolygonConfig.USDC,
      PolygonConfig.WETH,
      PolygonConfig.WBTC,
      PolygonConfig.POOL_FACTORY_PROD,
      PolygonConfig.NFT_TRACKER_PROD,
      PolygonConfig.SLIPPAGE_ACCUMULATOR_PROD,
      PolygonConfig.USD_PRICE_AGGREGATOR_PROD,
      PolygonConfig.PROXY_ADMIN
    )
  {}

  function setUp() public virtual override {
    super.setUp();
  }
}
