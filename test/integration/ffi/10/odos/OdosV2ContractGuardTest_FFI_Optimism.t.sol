// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {OdosV2ContractGuardTestSetup} from "test/integration/common/odos/OdosV2ContractGuardTestSetup.t.sol";
import {OptimismSetup} from "test/integration/utils/foundry/chains/OptimismSetup.t.sol";
import {OptimismConfig} from "test/integration/utils/foundry/config/OptimismConfig.sol";

/**
 * @notice FFI-dependent tests for Odos V2 Contract Guard
 * @dev This contract requires the FFI flag to be enabled in Foundry
 */
contract OdosV2ContractGuardTestFFIOptimism is OdosV2ContractGuardTestSetup, OptimismSetup {
  uint256 private odosTestForkBlockNumber = 134207968;
  address private odosRouterV2 = 0xCa423977156BB05b13A2BA3b76Bc5419E2fE9680;

  constructor()
    OdosV2ContractGuardTestSetup(odosRouterV2, OptimismConfig.CHAIN_ID)
    OptimismSetup(odosTestForkBlockNumber)
  {}

  function setUp() public override(OdosV2ContractGuardTestSetup, OptimismSetup) {
    super.setUp();
  }
}
