// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {DeploymentDryRunEthereum} from "test/integration/utils/foundry/dryRun/DeploymentDryRunEthereum.t.sol";
import {SafeSignerPauseTest} from "test/integration/common/core/SafeSignerPauseTest.t.sol";

contract SafeSignerPauseTestEthereum is SafeSignerPauseTest, DeploymentDryRunEthereum {
  constructor() DeploymentDryRunEthereum(24871080, new address[](0)) {}

  function setUp() public override(SafeSignerPauseTest, DeploymentDryRunEthereum) {
    SafeSignerPauseTest.setUp();
  }
}
