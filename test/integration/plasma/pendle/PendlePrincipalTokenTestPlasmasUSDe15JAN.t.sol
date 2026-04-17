// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {PendlePrincipalTokenTestSetup} from "test/integration/common/pendle/PendlePrincipalTokenTestSetup.t.sol";
import {PlasmaSetup} from "test/integration/utils/foundry/chains/PlasmaSetup.t.sol";
import {PlasmaConfig} from "test/integration/utils/foundry/config/PlasmaConfig.sol";

contract PendlePrincipalTokenTestPlasmasUSDe15JAN is PendlePrincipalTokenTestSetup, PlasmaSetup {
  address private constant PENDLE_ORACLE_PT_TO_SY_ETHENA_sUSDe_15JAN2026_1800_TWAP =
    0x15A0CFC054935AE485FCC12bD7f11bDA738865e2;
  address private constant PENDLE_MARKET_sUSDe_JAN_2026 = 0xe06C3B972BA630cCF3392cEcdbe070690b4e6b55;

  constructor()
    PendlePrincipalTokenTestSetup(
      PlasmaConfig.PENDLE_ROUTER_V4,
      PlasmaConfig.sUSDe,
      PlasmaConfig.sUSDe_CHAINLINK_ORACLE,
      PENDLE_MARKET_sUSDe_JAN_2026,
      PENDLE_ORACLE_PT_TO_SY_ETHENA_sUSDe_15JAN2026_1800_TWAP
    )
    PlasmaSetup(3941512)
  {}

  function setUp() public override(PendlePrincipalTokenTestSetup, PlasmaSetup) {
    super.setUp();
  }
}
