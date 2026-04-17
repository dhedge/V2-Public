// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {DeploymentDryRunHyperEVM} from "test/integration/utils/foundry/dryRun/DeploymentDryRunHyperEVM.t.sol";
import {SafeSignerPauseTest} from "test/integration/common/core/SafeSignerPauseTest.t.sol";

contract SafeSignerPauseTestHyperEVM is SafeSignerPauseTest, DeploymentDryRunHyperEVM {
  constructor() DeploymentDryRunHyperEVM(32362538, new address[](0)) {}

  function setUp() public override(SafeSignerPauseTest, DeploymentDryRunHyperEVM) {
    SafeSignerPauseTest.setUp();
  }
}
