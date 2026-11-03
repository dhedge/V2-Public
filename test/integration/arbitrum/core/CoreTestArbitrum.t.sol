// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {ReferralSystemTestSetup} from "test/integration/common/core/ReferralSystemTestSetup.t.sol";
import {ArbitrumSetup} from "test/integration/utils/foundry/chains/ArbitrumSetup.t.sol";
import {ForkBlocks} from "test/integration/utils/foundry/config/ForkBlocks.sol";

contract CoreTestArbitrum is ReferralSystemTestSetup, ArbitrumSetup {
  constructor() ReferralSystemTestSetup() ArbitrumSetup(ForkBlocks.ARBITRUM) {}

  function setUp() public virtual override(ReferralSystemTestSetup, ArbitrumSetup) {
    super.setUp();
  }
}
