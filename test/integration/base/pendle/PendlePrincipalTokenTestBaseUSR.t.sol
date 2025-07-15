// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {PendlePrincipalTokenTestSetup} from "test/integration/common/pendle/PendlePrincipalTokenTestSetup.t.sol";
import {PendlePrincipalTokenTestSharedData} from "test/integration/base/pendle/PendlePrincipalTokenTestSharedData.sol";
import {BaseSetup} from "test/integration/utils/foundry/chains/BaseSetup.t.sol";
import {EthereumConfig} from "test/integration/utils/foundry/config/EthereumConfig.sol";

contract PendlePrincipalTokenTestBaseUSR is PendlePrincipalTokenTestSetup, BaseSetup {
  address private constant PENDLE_MARKET_FACTORY_V3 = 0x59968008a703dC13E6beaECed644bdCe4ee45d13;
  address private constant RESOLV_USR = 0x35E5dB674D8e93a03d814FA0ADa70731efe8a4b9;
  address private constant RESOLV_USR_CHAINLINK_FEED = 0x4a595E0a62E50A2E5eC95A70c8E612F9746af006;
  address private constant PENDLE_MARKET_RESOLV_USR_25SEP2025 = 0x715509Bde846104cF2cCeBF6fdF7eF1BB874Bc45;
  address private constant PENDLE_ORACLE_PT_TO_SY_RESOLV_USR_25SEP2025_900_TWAP =
    0x553b07E07ebb880E4F55ac36B2D9dB0ab987a64D;

  constructor()
    PendlePrincipalTokenTestSetup(
      PENDLE_MARKET_FACTORY_V3,
      EthereumConfig.PENDLE_ROUTER_V4,
      RESOLV_USR,
      RESOLV_USR_CHAINLINK_FEED,
      PENDLE_MARKET_RESOLV_USR_25SEP2025,
      PENDLE_ORACLE_PT_TO_SY_RESOLV_USR_25SEP2025_900_TWAP
    )
    BaseSetup(PendlePrincipalTokenTestSharedData.FORK_BLOCK_NUMBER)
  {}

  function setUp() public override(PendlePrincipalTokenTestSetup, BaseSetup) {
    super.setUp();
  }
}
