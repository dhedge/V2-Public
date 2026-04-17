// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {DeploymentDryRunOptimism} from "test/integration/utils/foundry/dryRun/DeploymentDryRunOptimism.t.sol";
import {SafeSignerPauseTest} from "test/integration/common/core/SafeSignerPauseTest.t.sol";

contract SafeSignerPauseTestOptimism is SafeSignerPauseTest, DeploymentDryRunOptimism {
  constructor() DeploymentDryRunOptimism(150243656, new address[](0)) {}

  function setUp() public override(SafeSignerPauseTest, DeploymentDryRunOptimism) {
    SafeSignerPauseTest.setUp();
  }
}
