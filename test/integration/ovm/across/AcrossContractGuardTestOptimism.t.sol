// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {AcrossContractGuardTestSetup} from "test/integration/common/across/AcrossContractGuardTestSetup.t.sol";
import {OptimismSetup} from "test/integration/utils/foundry/chains/OptimismSetup.t.sol";
import {ArbitrumConfig} from "test/integration/utils/foundry/config/ArbitrumConfig.sol";

contract AcrossContractGuardTestOptimism is AcrossContractGuardTestSetup, OptimismSetup {
  uint256 private acrossTestForkBlockNumber = 132530362;
  address private acrossSpokePool = 0x6f26Bf09B1C792e3228e5467807a900A503c0281;
  address private approvedDestToken = ArbitrumConfig.USDC;
  uint256 private approvedDestChainId = ArbitrumConfig.CHAIN_ID;

  constructor()
    AcrossContractGuardTestSetup(acrossSpokePool, approvedDestToken, approvedDestChainId)
    OptimismSetup(acrossTestForkBlockNumber)
  {}

  function setUp() public override(AcrossContractGuardTestSetup, OptimismSetup) {
    super.setUp();
  }
}
