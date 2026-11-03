// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {DeploymentDryRunHyperEVM} from "test/integration/utils/foundry/dryRun/DeploymentDryRunHyperEVM.t.sol";
import {DeploymentDryRunTest} from "test/integration/utils/foundry/DeploymentDryRunTest.t.sol";
import {SafeSignerPauseTest} from "test/integration/common/core/SafeSignerPauseTest.t.sol";
import {ForkBlocks} from "test/integration/utils/foundry/config/ForkBlocks.sol";

contract SafeSignerPauseTestHyperEVM is SafeSignerPauseTest, DeploymentDryRunHyperEVM {
  constructor() DeploymentDryRunHyperEVM(ForkBlocks.HYPEREVM, new address[](0)) {}

  function setUp() public override(SafeSignerPauseTest, DeploymentDryRunHyperEVM) {
    SafeSignerPauseTest.setUp();
  }

  function _afterForkCreated() internal override(DeploymentDryRunTest, DeploymentDryRunHyperEVM) {
    DeploymentDryRunHyperEVM._afterForkCreated();
  }
}
