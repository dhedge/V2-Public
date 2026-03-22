// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {OdosContractGuardTestSetup} from "test/integration/common/odos/OdosContractGuardTestSetup.t.sol";
import {OptimismSetup} from "test/integration/utils/foundry/chains/OptimismSetup.t.sol";
import {OptimismConfig} from "test/integration/utils/foundry/config/OptimismConfig.sol";

/**
 * @notice FFI-dependent tests for Odos V2 Contract Guard
 * @dev This contract requires the FFI flag to be enabled in Foundry
 */
contract OdosV2ContractGuardTestFFIOptimism is OdosContractGuardTestSetup, OptimismSetup {
  uint256 private odosTestForkBlockNumber = 140660526;
  address private odosRouterV2 = 0xCa423977156BB05b13A2BA3b76Bc5419E2fE9680;

  constructor()
    OdosContractGuardTestSetup(odosRouterV2, OptimismConfig.CHAIN_ID, "v2")
    OptimismSetup(odosTestForkBlockNumber)
  {}

  function setUp() public override(OdosContractGuardTestSetup, OptimismSetup) {
    super.setUp();
  }
}
