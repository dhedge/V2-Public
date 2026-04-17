// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {DeploymentDryRunPolygon} from "test/integration/utils/foundry/dryRun/DeploymentDryRunPolygon.t.sol";
import {SafeSignerPauseTest} from "test/integration/common/core/SafeSignerPauseTest.t.sol";

contract SafeSignerPauseTestPolygon is SafeSignerPauseTest, DeploymentDryRunPolygon {
  constructor() DeploymentDryRunPolygon(85483070, new address[](0)) {}

  function setUp() public override(SafeSignerPauseTest, DeploymentDryRunPolygon) {
    SafeSignerPauseTest.setUp();
  }
}
