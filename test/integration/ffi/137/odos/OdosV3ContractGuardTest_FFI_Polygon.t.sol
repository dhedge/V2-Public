// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {OdosContractGuardTestSetup} from "test/integration/common/odos/OdosContractGuardTestSetup.t.sol";
import {PolygonSetup} from "test/integration/utils/foundry/chains/PolygonSetup.t.sol";
import {PolygonConfig} from "test/integration/utils/foundry/config/PolygonConfig.sol";
import {EthereumConfig} from "test/integration/utils/foundry/config/EthereumConfig.sol";

contract OdosV3ContractGuardTestFFIPolygon is OdosContractGuardTestSetup, PolygonSetup {
  uint256 private odosTestForkBlockNumber = 77296690;

  constructor()
    OdosContractGuardTestSetup(EthereumConfig.ODOS_V3_ROUTER, PolygonConfig.CHAIN_ID, "v3")
    PolygonSetup(odosTestForkBlockNumber)
  {}

  function setUp() public override(OdosContractGuardTestSetup, PolygonSetup) {
    super.setUp();
  }
}
