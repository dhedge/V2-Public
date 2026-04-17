// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {DeploymentDryRunPlasma} from "test/integration/utils/foundry/dryRun/DeploymentDryRunPlasma.t.sol";
import {SafeSignerPauseTest} from "test/integration/common/core/SafeSignerPauseTest.t.sol";

contract SafeSignerPauseTestPlasma is SafeSignerPauseTest, DeploymentDryRunPlasma {
  constructor() DeploymentDryRunPlasma(19154278, new address[](0)) {}

  function setUp() public override(SafeSignerPauseTest, DeploymentDryRunPlasma) {
    SafeSignerPauseTest.setUp();
  }
}
