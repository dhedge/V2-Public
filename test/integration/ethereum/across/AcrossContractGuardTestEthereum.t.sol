// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {AcrossContractGuardTestSetup} from "test/integration/common/across/AcrossContractGuardTestSetup.t.sol";
import {EthereumSetup} from "test/integration/utils/foundry/chains/EthereumSetup.t.sol";
import {HyperEVMConfig} from "test/integration/utils/foundry/config/HyperEVMConfig.sol";

contract AcrossContractGuardTestEthereum is AcrossContractGuardTestSetup, EthereumSetup {
  uint256 private acrossTestForkBlockNumber = 25400000;
  address private acrossSpokePool = 0x5c7BCd6E7De5423a257D81B442095A1a6ced35C5; // Across SpokePool on Ethereum
  address private approvedDestToken = HyperEVMConfig.USDC_TOKEN_ADDRESS; // USDC on HyperEVM
  uint256 private approvedDestChainId = HyperEVMConfig.CHAIN_ID; // 999

  constructor()
    AcrossContractGuardTestSetup(acrossSpokePool, approvedDestToken, approvedDestChainId)
    EthereumSetup(acrossTestForkBlockNumber)
  {}

  function setUp() public override(AcrossContractGuardTestSetup, EthereumSetup) {
    super.setUp();
  }
}
