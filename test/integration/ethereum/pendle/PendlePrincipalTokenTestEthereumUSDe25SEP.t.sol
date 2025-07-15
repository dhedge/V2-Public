// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {PendlePrincipalTokenTestSetup} from "test/integration/common/pendle/PendlePrincipalTokenTestSetup.t.sol";
import {EthereumSetup} from "test/integration/utils/foundry/chains/EthereumSetup.t.sol";
import {EthereumConfig} from "test/integration/utils/foundry/config/EthereumConfig.sol";

contract PendlePrincipalTokenTestEthereumUSDe25SEP is PendlePrincipalTokenTestSetup, EthereumSetup {
  address private constant PENDLE_MARKET_ETHENA_USDe_25SEP2025 = 0x6d98a2b6CDbF44939362a3E99793339Ba2016aF4;
  address private constant PENDLE_ORACLE_PT_TO_SY_ETHENA_USDe_25SEP2025_1800_TWAP =
    0xA6aC04cE586198693018Ad81859d22E440A6B6fc;

  constructor()
    PendlePrincipalTokenTestSetup(
      EthereumConfig.PENDLE_MARKET_FACTORY,
      EthereumConfig.PENDLE_ROUTER_V4,
      EthereumConfig.USDe,
      EthereumConfig.USDe_CHAINLINK_ORACLE,
      PENDLE_MARKET_ETHENA_USDe_25SEP2025,
      PENDLE_ORACLE_PT_TO_SY_ETHENA_USDe_25SEP2025_1800_TWAP
    )
    EthereumSetup(22788832)
  {}

  function setUp() public override(PendlePrincipalTokenTestSetup, EthereumSetup) {
    super.setUp();
  }
}
