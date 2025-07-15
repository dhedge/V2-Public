// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {PendlePrincipalTokenTestSetup} from "test/integration/common/pendle/PendlePrincipalTokenTestSetup.t.sol";
import {EthereumSetup} from "test/integration/utils/foundry/chains/EthereumSetup.t.sol";
import {EthereumConfig} from "test/integration/utils/foundry/config/EthereumConfig.sol";

contract PendlePrincipalTokenTestEthereumsUSDe25SEP is PendlePrincipalTokenTestSetup, EthereumSetup {
  address private constant PENDLE_ORACLE_PT_TO_SY_ETHENA_sUSDe_25SEP2025_1800_TWAP =
    0x1F3a9a671c0d326499099078568f2eba03AC2187;

  constructor()
    PendlePrincipalTokenTestSetup(
      EthereumConfig.PENDLE_MARKET_FACTORY,
      EthereumConfig.PENDLE_ROUTER_V4,
      EthereumConfig.sUSDe,
      EthereumConfig.sUSDe_CHAINLINK_ORACLE,
      EthereumConfig.PENDLE_MARKET_sUSDe_SEP_2025,
      PENDLE_ORACLE_PT_TO_SY_ETHENA_sUSDe_25SEP2025_1800_TWAP
    )
    EthereumSetup(22911305)
  {}

  function setUp() public override(PendlePrincipalTokenTestSetup, EthereumSetup) {
    super.setUp();
  }
}
