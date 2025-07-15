// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {OdosV2ContractGuardTestSetup} from "test/integration/common/odos/OdosV2ContractGuardTestSetup.t.sol";
import {BaseSetup} from "test/integration/utils/foundry/chains/BaseSetup.t.sol";
import {BaseConfig} from "test/integration/utils/foundry/config/BaseConfig.sol";

/**
 * @notice FFI-dependent tests for Odos V2 Contract Guard
 * @dev This contract requires the FFI flag to be enabled in Foundry
 */
contract OdosV2ContractGuardTestFFIBase is OdosV2ContractGuardTestSetup, BaseSetup {
  uint256 private odosTestForkBlockNumber = 28613184;
  address private dosRouterV2 = 0x19cEeAd7105607Cd444F5ad10dd51356436095a1;

  constructor() OdosV2ContractGuardTestSetup(dosRouterV2, BaseConfig.CHAIN_ID) BaseSetup(odosTestForkBlockNumber) {}

  function setUp() public override(OdosV2ContractGuardTestSetup, BaseSetup) {
    super.setUp();
  }
}
