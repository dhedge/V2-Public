// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {OdosContractGuardTestSetup} from "test/integration/common/odos/OdosContractGuardTestSetup.t.sol";
import {ArbitrumSetup} from "test/integration/utils/foundry/chains/ArbitrumSetup.t.sol";
import {ArbitrumConfig} from "test/integration/utils/foundry/config/ArbitrumConfig.sol";

/**
 * @notice FFI-dependent tests for Odos V2 Contract Guard
 * @dev This contract requires the FFI flag to be enabled in Foundry
 */
contract OdosV2ContractGuardTestFFIArbitrum is OdosContractGuardTestSetup, ArbitrumSetup {
  uint256 private odosTestForkBlockNumber = 375319408;
  address private odosRouterV2 = 0xa669e7A0d4b3e4Fa48af2dE86BD4CD7126Be4e13;

  constructor()
    OdosContractGuardTestSetup(odosRouterV2, ArbitrumConfig.CHAIN_ID, "v2")
    ArbitrumSetup(odosTestForkBlockNumber)
  {}

  function setUp() public override(OdosContractGuardTestSetup, ArbitrumSetup) {
    super.setUp();
  }
}
