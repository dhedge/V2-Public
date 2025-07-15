// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {OdosV2ContractGuardTestSetup} from "test/integration/common/odos/OdosV2ContractGuardTestSetup.t.sol";
import {ArbitrumSetup} from "test/integration/utils/foundry/chains/ArbitrumSetup.t.sol";
import {ArbitrumConfig} from "test/integration/utils/foundry/config/ArbitrumConfig.sol";

/**
 * @notice FFI-dependent tests for Odos V2 Contract Guard
 * @dev This contract requires the FFI flag to be enabled in Foundry
 */
contract OdosV2ContractGuardTestFFIArbitrum is OdosV2ContractGuardTestSetup, ArbitrumSetup {
  uint256 private odosTestForkBlockNumber = 323809750;
  address private odosRouterV2 = 0xa669e7A0d4b3e4Fa48af2dE86BD4CD7126Be4e13;

  constructor()
    OdosV2ContractGuardTestSetup(odosRouterV2, ArbitrumConfig.CHAIN_ID)
    ArbitrumSetup(odosTestForkBlockNumber)
  {}

  function setUp() public override(OdosV2ContractGuardTestSetup, ArbitrumSetup) {
    super.setUp();
  }
}
