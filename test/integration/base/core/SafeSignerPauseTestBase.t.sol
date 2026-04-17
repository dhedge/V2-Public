// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {DeploymentDryRunBase} from "test/integration/utils/foundry/dryRun/DeploymentDryRunBase.t.sol";
import {SafeSignerPauseTest} from "test/integration/common/core/SafeSignerPauseTest.t.sol";

contract SafeSignerPauseTestBase is SafeSignerPauseTest, DeploymentDryRunBase {
  constructor() DeploymentDryRunBase(44648328, new address[](0)) {}

  function setUp() public override(SafeSignerPauseTest, DeploymentDryRunBase) {
    SafeSignerPauseTest.setUp();
  }
}
