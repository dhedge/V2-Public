// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {OdosV2ContractGuardTestSetup} from "test/integration/common/odos/OdosV2ContractGuardTestSetup.t.sol";
import {PolygonSetup} from "test/integration/utils/foundry/chains/PolygonSetup.t.sol";
import {PolygonConfig} from "test/integration/utils/foundry/config/PolygonConfig.sol";

/**
 * @notice FFI-dependent tests for Odos V2 Contract Guard
 * @dev This contract requires the FFI flag to be enabled in Foundry
 */
contract OdosV2ContractGuardTestFFIPolygon is OdosV2ContractGuardTestSetup, PolygonSetup {
  uint256 private odosTestForkBlockNumber = 70032666;
  address private odosRouterV2 = 0x4E3288c9ca110bCC82bf38F09A7b425c095d92Bf;

  constructor()
    OdosV2ContractGuardTestSetup(odosRouterV2, PolygonConfig.CHAIN_ID)
    PolygonSetup(odosTestForkBlockNumber)
  {}

  function setUp() public override(OdosV2ContractGuardTestSetup, PolygonSetup) {
    super.setUp();
  }
}
