// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {OdosContractGuardTestSetup} from "test/integration/common/odos/OdosContractGuardTestSetup.t.sol";
import {BaseSetup} from "test/integration/utils/foundry/chains/BaseSetup.t.sol";
import {BaseConfig} from "test/integration/utils/foundry/config/BaseConfig.sol";
import {EthereumConfig} from "test/integration/utils/foundry/config/EthereumConfig.sol";

contract OdosV3ContractGuardTestFFIBase is OdosContractGuardTestSetup, BaseSetup {
  uint256 private odosTestForkBlockNumber = 36446508;

  constructor()
    OdosContractGuardTestSetup(EthereumConfig.ODOS_V3_ROUTER, BaseConfig.CHAIN_ID, "v3")
    BaseSetup(odosTestForkBlockNumber)
  {}

  function setUp() public override(OdosContractGuardTestSetup, BaseSetup) {
    super.setUp();
  }
}
