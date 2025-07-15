// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {AcrossContractGuardTestSetup} from "test/integration/common/across/AcrossContractGuardTestSetup.t.sol";
import {ArbitrumSetup} from "test/integration/utils/foundry/chains/ArbitrumSetup.t.sol";
import {BaseConfig} from "test/integration/utils/foundry/config/BaseConfig.sol";

contract AcrossContractGuardTestArbitrum is AcrossContractGuardTestSetup, ArbitrumSetup {
  uint256 private acrossTestForkBlockNumber = 310164002;
  address private acrossSpokePool = 0xe35e9842fceaCA96570B734083f4a58e8F7C5f2A;
  address private approvedDestToken = BaseConfig.USDC;
  uint256 private approvedDestChainId = BaseConfig.CHAIN_ID;

  constructor()
    AcrossContractGuardTestSetup(acrossSpokePool, approvedDestToken, approvedDestChainId)
    ArbitrumSetup(acrossTestForkBlockNumber)
  {}

  function setUp() public override(AcrossContractGuardTestSetup, ArbitrumSetup) {
    super.setUp();
  }
}
