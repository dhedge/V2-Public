// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {PendlePrincipalTokenTestSetup} from "test/integration/common/pendle/PendlePrincipalTokenTestSetup.t.sol";
import {EthereumSetup} from "test/integration/utils/foundry/chains/EthereumSetup.t.sol";
import {EthereumConfig} from "test/integration/utils/foundry/config/EthereumConfig.sol";

contract PendlePrincipalTokenTestEthereumsUSDe05FEB2026 is PendlePrincipalTokenTestSetup, EthereumSetup {
  address private constant PENDLE_MARKET_sUSDe_05FEB2026 = 0xed81f8bA2941C3979de2265C295748a6b6956567;
  address private constant PENDLE_ORACLE_PT_TO_SY_ETHENA_sUSDe_05FEB2026_1800_TWAP =
    0xe720099E912d0Fc92011Dc8AA7eBC139a127bF71;
  address private constant CURRENT_CUSTOM_sUSDE_ORACLE = 0x0d3F8B643e3769c364f55592e3840b51bCDD1Df5;

  constructor()
    PendlePrincipalTokenTestSetup(
      EthereumConfig.PENDLE_ROUTER_V4,
      EthereumConfig.sUSDe,
      CURRENT_CUSTOM_sUSDE_ORACLE,
      PENDLE_MARKET_sUSDe_05FEB2026,
      PENDLE_ORACLE_PT_TO_SY_ETHENA_sUSDe_05FEB2026_1800_TWAP
    )
    EthereumSetup(23742286)
  {}

  function setUp() public override(PendlePrincipalTokenTestSetup, EthereumSetup) {
    super.setUp();
  }
}
