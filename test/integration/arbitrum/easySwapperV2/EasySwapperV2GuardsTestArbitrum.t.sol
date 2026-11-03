// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {EasySwapperV2GuardsTestSetup} from "test/integration/common/easySwapperV2/EasySwapperV2GuardsTestSetup.t.sol";
import {ArbitrumSetup} from "test/integration/utils/foundry/chains/ArbitrumSetup.t.sol";
import {ForkBlocks} from "test/integration/utils/foundry/config/ForkBlocks.sol";

contract EasySwapperV2GuardsTestArbitrum is EasySwapperV2GuardsTestSetup, ArbitrumSetup {
  constructor() ArbitrumSetup(ForkBlocks.ARBITRUM) {}

  function setUp() public override(EasySwapperV2GuardsTestSetup, ArbitrumSetup) {
    super.setUp();
  }
}
