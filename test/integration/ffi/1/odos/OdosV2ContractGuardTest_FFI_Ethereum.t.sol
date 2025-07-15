// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {OdosV2ContractGuardTestSetup} from "test/integration/common/odos/OdosV2ContractGuardTestSetup.t.sol";
import {EthereumSetup} from "test/integration/utils/foundry/chains/EthereumSetup.t.sol";
import {EthereumConfig} from "test/integration/utils/foundry/config/EthereumConfig.sol";

/**
 * @notice FFI-dependent tests for Odos V2 Contract Guard
 * @dev This contract requires the FFI flag to be enabled in Foundry
 */
contract OdosV2ContractGuardTestFFIEthereum is OdosV2ContractGuardTestSetup, EthereumSetup {
  uint256 private odosTestForkBlockNumber = 22776190;
  address private odosRouterV2 = 0xCf5540fFFCdC3d510B18bFcA6d2b9987b0772559;

  constructor()
    OdosV2ContractGuardTestSetup(odosRouterV2, EthereumConfig.CHAIN_ID)
    EthereumSetup(odosTestForkBlockNumber)
  {}

  function setUp() public override(OdosV2ContractGuardTestSetup, EthereumSetup) {
    super.setUp();
  }
}
