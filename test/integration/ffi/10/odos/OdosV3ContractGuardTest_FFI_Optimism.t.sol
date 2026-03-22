// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {OdosContractGuardTestSetup} from "test/integration/common/odos/OdosContractGuardTestSetup.t.sol";
import {OptimismSetup} from "test/integration/utils/foundry/chains/OptimismSetup.t.sol";
import {OptimismConfig} from "test/integration/utils/foundry/config/OptimismConfig.sol";
import {EthereumConfig} from "test/integration/utils/foundry/config/EthereumConfig.sol";

contract OdosV3ContractGuardTestFFIOptimism is OdosContractGuardTestSetup, OptimismSetup {
  uint256 private odosTestForkBlockNumber = 142041894;

  constructor()
    OdosContractGuardTestSetup(EthereumConfig.ODOS_V3_ROUTER, OptimismConfig.CHAIN_ID, "v3")
    OptimismSetup(odosTestForkBlockNumber)
  {}

  function setUp() public override(OdosContractGuardTestSetup, OptimismSetup) {
    super.setUp();
  }
}
