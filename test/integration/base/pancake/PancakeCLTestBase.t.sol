// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {PancakeCLTestSetup} from "test/integration/common/pancake/PancakeCLTestSetup.t.sol";
import {BaseSetup} from "test/integration/utils/foundry/chains/BaseSetup.t.sol";

contract PancakeCLTestBase is PancakeCLTestSetup, BaseSetup {
  uint256 internal FORK_BLOCK_NUMBER = 25947200;

  constructor()
    PancakeCLTestSetup(
      0x46A15B0b27311cedF172AB29E4f4766fbE7F4364,
      0xC6A2Db661D5a5690172d8eB0a7DEA2d3008665A3,
      0x3055913c90Fcc1A6CE9a358911721eEb942013A1
    )
    BaseSetup(FORK_BLOCK_NUMBER)
  {}

  function setUp() public override(PancakeCLTestSetup, BaseSetup) {
    super.setUp();
  }
}
