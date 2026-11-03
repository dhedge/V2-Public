// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {DeploymentDryRunBase} from "test/integration/utils/foundry/dryRun/DeploymentDryRunBase.t.sol";
import {SafeSignerPauseTest} from "test/integration/common/core/SafeSignerPauseTest.t.sol";
import {ForkBlocks} from "test/integration/utils/foundry/config/ForkBlocks.sol";

contract SafeSignerPauseTestBase is SafeSignerPauseTest, DeploymentDryRunBase {
  constructor() DeploymentDryRunBase(ForkBlocks.BASE, new address[](0)) {}

  function setUp() public override(SafeSignerPauseTest, DeploymentDryRunBase) {
    SafeSignerPauseTest.setUp();
  }
}
