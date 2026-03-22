// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma abicoder v2;

import {CowSwapTestSetup} from "test/integration/common/cowSwap/CowSwapTestSetup.t.sol";
import {BaseSetup} from "test/integration/utils/foundry/chains/BaseSetup.t.sol";
import {BaseConfig} from "test/integration/utils/foundry/config/BaseConfig.sol";

contract CowSwapTestBase is CowSwapTestSetup, BaseSetup {
  address private constant GPV2_VAULT_RELAYER = 0xC92E8bdf79f0507f65a392b0ab4667716BFE0110;

  constructor() BaseSetup(41421290) CowSwapTestSetup(BaseConfig.GPV2_SETTLEMENT, GPV2_VAULT_RELAYER) {}

  function setUp() public override(CowSwapTestSetup, BaseSetup) {
    super.setUp();
  }
}
