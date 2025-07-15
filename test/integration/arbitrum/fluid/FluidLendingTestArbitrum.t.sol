// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {FluidLendingTestSetup} from "test/integration/common/fluid/FluidLendingTestSetup.t.sol";
import {ArbitrumSetup} from "test/integration/utils/foundry/chains/ArbitrumSetup.t.sol";

contract FluidLendingTestArbitrum is FluidLendingTestSetup, ArbitrumSetup {
  uint256 private testForkBlockNumber = 316414754;

  constructor()
    FluidLendingTestSetup(0x45Df0656F8aDf017590009d2f1898eeca4F0a205, 0x1A996cb54bb95462040408C06122D45D6Cdb6096)
    ArbitrumSetup(testForkBlockNumber)
  {}

  function setUp() public override(FluidLendingTestSetup, ArbitrumSetup) {
    super.setUp();
  }
}
