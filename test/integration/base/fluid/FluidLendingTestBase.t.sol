// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {FluidLendingTestSetup} from "test/integration/common/fluid/FluidLendingTestSetup.t.sol";
import {BaseSetup} from "test/integration/utils/foundry/chains/BaseSetup.t.sol";
import {ForkBlocks} from "test/integration/utils/foundry/config/ForkBlocks.sol";

contract FluidLendingTestBase is FluidLendingTestSetup, BaseSetup {
  constructor()
    FluidLendingTestSetup(0x9272D6153133175175Bc276512B2336BE3931CE9, 0xf42f5795D9ac7e9D757dB633D693cD548Cfd9169)
    BaseSetup(ForkBlocks.BASE)
  {}

  function setUp() public override(FluidLendingTestSetup, BaseSetup) {
    super.setUp();
  }
}
