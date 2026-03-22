// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {OdosContractGuardTestSetup} from "test/integration/common/odos/OdosContractGuardTestSetup.t.sol";
import {EthereumSetup} from "test/integration/utils/foundry/chains/EthereumSetup.t.sol";
import {EthereumConfig} from "test/integration/utils/foundry/config/EthereumConfig.sol";

contract OdosV3ContractGuardTestFFIEthereum is OdosContractGuardTestSetup, EthereumSetup {
  uint256 private odosTestForkBlockNumber = 23512832;

  constructor()
    OdosContractGuardTestSetup(EthereumConfig.ODOS_V3_ROUTER, EthereumConfig.CHAIN_ID, "v3")
    EthereumSetup(odosTestForkBlockNumber)
  {}

  function setUp() public override(OdosContractGuardTestSetup, EthereumSetup) {
    super.setUp();
  }
}
