// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {OdosContractGuardTestSetup} from "test/integration/common/odos/OdosContractGuardTestSetup.t.sol";
import {ArbitrumSetup} from "test/integration/utils/foundry/chains/ArbitrumSetup.t.sol";
import {ArbitrumConfig} from "test/integration/utils/foundry/config/ArbitrumConfig.sol";
import {EthereumConfig} from "test/integration/utils/foundry/config/EthereumConfig.sol";

contract OdosV3ContractGuardTestFFIArbitrum is OdosContractGuardTestSetup, ArbitrumSetup {
  uint256 private odosTestForkBlockNumber = 386364882;

  constructor()
    OdosContractGuardTestSetup(EthereumConfig.ODOS_V3_ROUTER, ArbitrumConfig.CHAIN_ID, "v3")
    ArbitrumSetup(odosTestForkBlockNumber)
  {}

  function setUp() public override(OdosContractGuardTestSetup, ArbitrumSetup) {
    super.setUp();
  }
}
