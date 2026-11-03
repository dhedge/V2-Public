// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {DeploymentDryRunArbitrum} from "test/integration/utils/foundry/dryRun/DeploymentDryRunArbitrum.t.sol";
import {SafeSignerPauseTest} from "test/integration/common/core/SafeSignerPauseTest.t.sol";
import {ForkBlocks} from "test/integration/utils/foundry/config/ForkBlocks.sol";

contract SafeSignerPauseTestArbitrum is SafeSignerPauseTest, DeploymentDryRunArbitrum {
  constructor() DeploymentDryRunArbitrum(ForkBlocks.ARBITRUM, new address[](0)) {}

  function setUp() public override(SafeSignerPauseTest, DeploymentDryRunArbitrum) {
    SafeSignerPauseTest.setUp();
  }
}
