// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {OdosContractGuardTestSetup} from "test/integration/common/odos/OdosContractGuardTestSetup.t.sol";
import {EthereumSetup} from "test/integration/utils/foundry/chains/EthereumSetup.t.sol";
import {EthereumConfig} from "test/integration/utils/foundry/config/EthereumConfig.sol";

/**
 * @notice FFI-dependent tests for Odos V2 Contract Guard
 * @dev This contract requires the FFI flag to be enabled in Foundry
 */
contract OdosV2ContractGuardTestFFIEthereum is OdosContractGuardTestSetup, EthereumSetup {
  uint256 private odosTestForkBlockNumber = 23284038;
  address private odosRouterV2 = 0xCf5540fFFCdC3d510B18bFcA6d2b9987b0772559;

  constructor()
    OdosContractGuardTestSetup(odosRouterV2, EthereumConfig.CHAIN_ID, "v2")
    EthereumSetup(odosTestForkBlockNumber)
  {}

  function setUp() public override(OdosContractGuardTestSetup, EthereumSetup) {
    super.setUp();
  }
}
