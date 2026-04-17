// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {PendlePrincipalTokenTestSetup} from "test/integration/common/pendle/PendlePrincipalTokenTestSetup.t.sol";
import {ArbitrumSetup} from "test/integration/utils/foundry/chains/ArbitrumSetup.t.sol";
import {ArbitrumConfig} from "test/integration/utils/foundry/config/ArbitrumConfig.sol";

contract PendlePrincipalTokenTestArbitrumWstETH25JUN2026 is PendlePrincipalTokenTestSetup, ArbitrumSetup {
  address private constant PENDLE_MARKET_wstETH_25JUN2026 = 0xf78452e0f5C0B95fc5dC8353B8CD1e06E53fa25B;
  address private constant PENDLE_ORACLE_PT_TO_SY_wstETH_25JUN2026_1800_TWAP =
    0xEE667D40493dB72a94e08EC0948288a358539961;

  constructor()
    PendlePrincipalTokenTestSetup(
      ArbitrumConfig.PENDLE_ROUTER_V4,
      ArbitrumConfig.WSTETH,
      ArbitrumConfig.WSTETH_ORACLE,
      PENDLE_MARKET_wstETH_25JUN2026,
      PENDLE_ORACLE_PT_TO_SY_wstETH_25JUN2026_1800_TWAP
    )
    ArbitrumSetup(445379351)
  {}

  function setUp() public override(PendlePrincipalTokenTestSetup, ArbitrumSetup) {
    super.setUp();
  }

  function _underlyingDepositAmount() internal pure override returns (uint256) {
    return 10;
  }
}
