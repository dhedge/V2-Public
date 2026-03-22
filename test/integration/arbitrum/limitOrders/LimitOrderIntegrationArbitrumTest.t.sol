// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {LimitOrderIntegrationTestSetup} from "test/integration/common/limitOrders/LimitOrderIntegrationTestSetup.t.sol";
import {ArbitrumSetup} from "test/integration/utils/foundry/chains/ArbitrumSetup.t.sol";

contract LimitOrderIntegrationArbitrumTest is LimitOrderIntegrationTestSetup, ArbitrumSetup {
  uint256 private testForkBlockNumber = 397486930;

  constructor() LimitOrderIntegrationTestSetup() ArbitrumSetup(testForkBlockNumber) {}

  function setUp() public override(LimitOrderIntegrationTestSetup, ArbitrumSetup) {
    super.setUp();
  }
}
