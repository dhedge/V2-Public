// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {LimitOrderIntegrationTestSetup} from "test/integration/common/limitOrders/limitSells/LimitOrderIntegrationTestSetup.t.sol";
import {ArbitrumSetup} from "test/integration/utils/foundry/chains/ArbitrumSetup.t.sol";
import {ForkBlocks} from "test/integration/utils/foundry/config/ForkBlocks.sol";

contract LimitOrderIntegrationArbitrumTest is LimitOrderIntegrationTestSetup, ArbitrumSetup {
  constructor() LimitOrderIntegrationTestSetup() ArbitrumSetup(ForkBlocks.ARBITRUM) {}

  function setUp() public override(LimitOrderIntegrationTestSetup, ArbitrumSetup) {
    super.setUp();
  }
}
