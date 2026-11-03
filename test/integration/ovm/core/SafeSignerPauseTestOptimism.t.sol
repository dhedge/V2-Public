// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {DeploymentDryRunOptimism} from "test/integration/utils/foundry/dryRun/DeploymentDryRunOptimism.t.sol";
import {SafeSignerPauseTest} from "test/integration/common/core/SafeSignerPauseTest.t.sol";
import {ForkBlocks} from "test/integration/utils/foundry/config/ForkBlocks.sol";

contract SafeSignerPauseTestOptimism is SafeSignerPauseTest, DeploymentDryRunOptimism {
  constructor() DeploymentDryRunOptimism(ForkBlocks.OPTIMISM, new address[](0)) {}

  function setUp() public override(SafeSignerPauseTest, DeploymentDryRunOptimism) {
    SafeSignerPauseTest.setUp();
  }
}
