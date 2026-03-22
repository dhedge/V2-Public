// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma abicoder v2;

import {FlatMoneyOptionsLPTestSetup} from "test/integration/common/flatMoney/FlatMoneyOptionsLPTestSetup.t.sol";
import {ArbitrumSetup} from "test/integration/utils/foundry/chains/ArbitrumSetup.t.sol";
import {ArbitrumConfig} from "test/integration/utils/foundry/config/ArbitrumConfig.sol";

contract FlatMoneyOptionsLPTestArbitrum is FlatMoneyOptionsLPTestSetup, ArbitrumSetup {
  address private constant OPTIONS_VIEWER = 0x487CFb84C874036240BaEe66d6C3042316af9F34;
  uint256 private constant KEEPER_FEE = 228;

  constructor()
    FlatMoneyOptionsLPTestSetup(
      ArbitrumConfig.FLAT_MONEY_V2_OPTIONS_VAULT,
      OPTIONS_VIEWER,
      ArbitrumConfig.WBTC_CHAINLINK_ORACLE,
      KEEPER_FEE
    )
    ArbitrumSetup(430626098)
  {}

  function setUp() public override(FlatMoneyOptionsLPTestSetup, ArbitrumSetup) {
    super.setUp();
  }
}
