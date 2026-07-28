// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {PendlePrincipalTokenTestSetup} from "test/integration/common/pendle/PendlePrincipalTokenTestSetup.t.sol";
import {EthereumSetup} from "test/integration/utils/foundry/chains/EthereumSetup.t.sol";
import {EthereumConfig} from "test/integration/utils/foundry/config/EthereumConfig.sol";

contract PendlePrincipalTokenTestEthereumApxUSD05NOV2026 is PendlePrincipalTokenTestSetup, EthereumSetup {
  address private constant APX_USD = 0x98A878b1Cd98131B271883B390f68D2c90674665;
  address private constant APX_USD_CHAINLINK_ORACLE = 0x651b101f72F82630cf59c68E6EE4305aFBd3B1F5;
  address private constant PENDLE_MARKET_APX_USD_05NOV2026 = 0xaf0349FB9B1bA07D34381870c59b560b31412660;
  address private constant PENDLE_ORACLE_PT_TO_SY_APX_USD_05NOV2026_1800_TWAP =
    0xc83Cb56B14c4172455EA39FE7eD5CcdDEF081a62;

  constructor()
    PendlePrincipalTokenTestSetup(
      EthereumConfig.PENDLE_ROUTER_V4,
      APX_USD,
      APX_USD_CHAINLINK_ORACLE,
      PENDLE_MARKET_APX_USD_05NOV2026,
      PENDLE_ORACLE_PT_TO_SY_APX_USD_05NOV2026_1800_TWAP
    )
    EthereumSetup(25144254)
  {}

  function setUp() public override(PendlePrincipalTokenTestSetup, EthereumSetup) {
    super.setUp();
  }
}
