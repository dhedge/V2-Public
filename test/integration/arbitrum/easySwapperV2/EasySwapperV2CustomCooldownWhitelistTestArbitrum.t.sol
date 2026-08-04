// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

// solhint-disable-next-line max-line-length
import {EasySwapperV2CustomCooldownWhitelistTestSetup} from "test/integration/common/easySwapperV2/EasySwapperV2CustomCooldownWhitelistTestSetup.t.sol";
import {ArbitrumSetup} from "test/integration/utils/foundry/chains/ArbitrumSetup.t.sol";

contract EasySwapperV2CustomCooldownWhitelistTestArbitrum is
  EasySwapperV2CustomCooldownWhitelistTestSetup,
  ArbitrumSetup
{
  constructor() EasySwapperV2CustomCooldownWhitelistTestSetup() ArbitrumSetup(489036888) {}

  function setUp() public override(EasySwapperV2CustomCooldownWhitelistTestSetup, ArbitrumSetup) {
    super.setUp();
  }
}
