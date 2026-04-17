// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {PendlePrincipalTokenTestSetup} from "test/integration/common/pendle/PendlePrincipalTokenTestSetup.t.sol";
import {PlasmaSetup} from "test/integration/utils/foundry/chains/PlasmaSetup.t.sol";
import {PlasmaConfig} from "test/integration/utils/foundry/config/PlasmaConfig.sol";

contract PendlePrincipalTokenTestPlasmaUSDe15JAN is PendlePrincipalTokenTestSetup, PlasmaSetup {
  address private constant PENDLE_ORACLE_PT_TO_SY_ETHENA_USDe_15JAN2026_1800_TWAP =
    0x706cEc110C2a755F05315A3Ad6d45Ac56e624A45;
  address private constant PENDLE_MARKET_USDe_JAN_2026 = 0xFD3eB62302fa3cBc3c7e59e887b92dBBc814285D;

  constructor()
    PendlePrincipalTokenTestSetup(
      PlasmaConfig.PENDLE_ROUTER_V4,
      PlasmaConfig.USDe,
      PlasmaConfig.USDe_CHAINLINK_ORACLE,
      PENDLE_MARKET_USDe_JAN_2026,
      PENDLE_ORACLE_PT_TO_SY_ETHENA_USDe_15JAN2026_1800_TWAP
    )
    PlasmaSetup(3941512)
  {}

  function setUp() public override(PendlePrincipalTokenTestSetup, PlasmaSetup) {
    super.setUp();
  }
}
