// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {EasySwapperV2TestSetup} from "test/integration/common/easySwapperV2/EasySwapperV2TestSetup.t.sol";
import {ArbitrumSetup} from "test/integration/utils/foundry/chains/ArbitrumSetup.t.sol";

contract EasySwapperV2TestArbitrum is EasySwapperV2TestSetup, ArbitrumSetup {
  constructor() ArbitrumSetup(489036888) {}

  function setUp() public override(EasySwapperV2TestSetup, ArbitrumSetup) {
    super.setUp();
  }
}
