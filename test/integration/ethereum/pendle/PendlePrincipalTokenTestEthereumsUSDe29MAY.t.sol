// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {PendlePrincipalTokenTestSetup} from "test/integration/common/pendle/PendlePrincipalTokenTestSetup.t.sol";
import {EthereumSetup} from "test/integration/utils/foundry/chains/EthereumSetup.t.sol";
import {EthereumConfig} from "test/integration/utils/foundry/config/EthereumConfig.sol";

contract PendlePrincipalTokenTestEthereumsUSDe29MAY is PendlePrincipalTokenTestSetup, EthereumSetup {
  address private constant PENDLE_MARKET_ETHENA_sUSDe_29MAY2025 = 0xB162B764044697cf03617C2EFbcB1f42e31E4766;
  address private constant PENDLE_ORACLE_PT_TO_SY_ETHENA_sUSDe_29MAY2025_900_TWAP =
    0xFD2261fadD243dA52C3409310Cc8f3A35545c85F;

  constructor()
    PendlePrincipalTokenTestSetup(
      EthereumConfig.PENDLE_MARKET_FACTORY,
      EthereumConfig.PENDLE_ROUTER_V4,
      EthereumConfig.sUSDe,
      EthereumConfig.sUSDe_CHAINLINK_ORACLE,
      PENDLE_MARKET_ETHENA_sUSDe_29MAY2025,
      PENDLE_ORACLE_PT_TO_SY_ETHENA_sUSDe_29MAY2025_900_TWAP
    )
    EthereumSetup(22482398)
  {}

  function setUp() public override(PendlePrincipalTokenTestSetup, EthereumSetup) {
    super.setUp();
  }
}
