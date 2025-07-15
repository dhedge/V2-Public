// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {PancakeCLTestSetup} from "test/integration/common/pancake/PancakeCLTestSetup.t.sol";
import {ArbitrumSetup} from "test/integration/utils/foundry/chains/ArbitrumSetup.t.sol";

contract PancakeCLTestArbitrum is PancakeCLTestSetup, ArbitrumSetup {
  uint256 internal FORK_BLOCK_NUMBER = 317710667;

  constructor()
    PancakeCLTestSetup(
      0x46A15B0b27311cedF172AB29E4f4766fbE7F4364,
      0x5e09ACf80C0296740eC5d6F643005a4ef8DaA694,
      0x1b896893dfc86bb67Cf57767298b9073D2c1bA2c
    )
    ArbitrumSetup(FORK_BLOCK_NUMBER)
  {}

  function setUp() public override(PancakeCLTestSetup, ArbitrumSetup) {
    super.setUp();
  }
}
