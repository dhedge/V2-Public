// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {AcrossContractGuardTestSetup} from "test/integration/common/across/AcrossContractGuardTestSetup.t.sol";
import {BaseSetup} from "test/integration/utils/foundry/chains/BaseSetup.t.sol";
import {ArbitrumConfig} from "test/integration/utils/foundry/config/ArbitrumConfig.sol";

contract AcrossContractGuardTestBase is AcrossContractGuardTestSetup, BaseSetup {
  uint256 private acrossTestForkBlockNumber = 26934420;
  address private acrossSpokePool = 0x09aea4b2242abC8bb4BB78D537A67a245A7bEC64;
  address private approvedDestToken = ArbitrumConfig.USDC;
  uint256 private approvedDestChainId = ArbitrumConfig.CHAIN_ID;

  constructor()
    AcrossContractGuardTestSetup(acrossSpokePool, approvedDestToken, approvedDestChainId)
    BaseSetup(acrossTestForkBlockNumber)
  {}

  function setUp() public override(AcrossContractGuardTestSetup, BaseSetup) {
    super.setUp();
  }
}
