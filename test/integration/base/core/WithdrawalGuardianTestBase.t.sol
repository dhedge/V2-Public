// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {WithdrawalGuardianTestSetup} from "test/integration/common/core/WithdrawalGuardianTestSetup.t.sol";
import {BaseSetup} from "test/integration/utils/foundry/chains/BaseSetup.t.sol";

contract WithdrawalGuardianTestBase is WithdrawalGuardianTestSetup, BaseSetup {
  uint256 private testForkBlockNumber = 47802544;

  constructor() BaseSetup(testForkBlockNumber) {}

  function setUp() public override(WithdrawalGuardianTestSetup, BaseSetup) {
    super.setUp();
  }
}
