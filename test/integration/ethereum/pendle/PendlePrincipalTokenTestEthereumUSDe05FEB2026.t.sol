// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {PendlePrincipalTokenTestSetup} from "test/integration/common/pendle/PendlePrincipalTokenTestSetup.t.sol";
import {EthereumSetup} from "test/integration/utils/foundry/chains/EthereumSetup.t.sol";
import {EthereumConfig} from "test/integration/utils/foundry/config/EthereumConfig.sol";

contract PendlePrincipalTokenTestEthereumUSDe05FEB2026 is PendlePrincipalTokenTestSetup, EthereumSetup {
  address private constant PENDLE_MARKET_USDe_05FEB2026 = 0xAADBC004DAcF10e1fdbd87ca1a40ecAF77CC5B02;
  address private constant PENDLE_ORACLE_PT_TO_SY_ETHENA_USDe_05FEB2026_1800_TWAP =
    0x989B4cA516deEc59DBB7B8bec4781aA963997a26;
  address private constant CURRENT_CUSTOM_USDe_ORACLE = 0x8540dde50E33889Ea7BEf32385cd757d67D31e86;

  constructor()
    PendlePrincipalTokenTestSetup(
      EthereumConfig.PENDLE_ROUTER_V4,
      EthereumConfig.USDe,
      CURRENT_CUSTOM_USDe_ORACLE,
      PENDLE_MARKET_USDe_05FEB2026,
      PENDLE_ORACLE_PT_TO_SY_ETHENA_USDe_05FEB2026_1800_TWAP
    )
    EthereumSetup(23742286)
  {}

  function setUp() public override(PendlePrincipalTokenTestSetup, EthereumSetup) {
    super.setUp();
  }
}
