// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {FluidLendingTestSetup} from "test/integration/common/fluid/FluidLendingTestSetup.t.sol";
import {BaseSetup} from "test/integration/utils/foundry/chains/BaseSetup.t.sol";

contract FluidLendingTestBase is FluidLendingTestSetup, BaseSetup {
  uint256 private testForkBlockNumber = 27680890;

  constructor()
    FluidLendingTestSetup(0x9272D6153133175175Bc276512B2336BE3931CE9, 0xf42f5795D9ac7e9D757dB633D693cD548Cfd9169)
    BaseSetup(testForkBlockNumber)
  {}

  function setUp() public override(FluidLendingTestSetup, BaseSetup) {
    super.setUp();
  }
}
