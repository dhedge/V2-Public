// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {FluidLendingTestSetup} from "test/integration/common/fluid/FluidLendingTestSetup.t.sol";
import {ArbitrumSetup} from "test/integration/utils/foundry/chains/ArbitrumSetup.t.sol";
import {ForkBlocks} from "test/integration/utils/foundry/config/ForkBlocks.sol";

contract FluidLendingTestArbitrum is FluidLendingTestSetup, ArbitrumSetup {
  constructor()
    FluidLendingTestSetup(0x45Df0656F8aDf017590009d2f1898eeca4F0a205, 0x1A996cb54bb95462040408C06122D45D6Cdb6096)
    ArbitrumSetup(ForkBlocks.ARBITRUM)
  {}

  function setUp() public override(FluidLendingTestSetup, ArbitrumSetup) {
    super.setUp();
  }
}
