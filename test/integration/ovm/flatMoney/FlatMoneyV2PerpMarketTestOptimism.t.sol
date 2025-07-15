// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma abicoder v2;

import {FlatMoneyV2PerpMarketTestSetup} from "test/integration/common/flatMoney/FlatMoneyV2PerpMarketTestSetup.t.sol";
import {FlatMoneyV2PerpMarketTestSharedData} from "test/integration/ovm/flatMoney/FlatMoneyV2PerpMarketTestSharedData.sol";
import {OptimismSetup} from "test/integration/utils/foundry/chains/OptimismSetup.t.sol";
import {OptimismConfig} from "test/integration/utils/foundry/config/OptimismConfig.sol";

contract FlatMoneyV2PerpMarketTestOptimism is FlatMoneyV2PerpMarketTestSetup, OptimismSetup {
  address private constant FLATCOIN_VAULT = 0x86C7b9640302082B0dF78023F930d8612bFcaD3f;
  address private constant PERP_VIEWER = 0x1F1A5f8c2d133b0c663cf85943B8E73ec143DB16;
  uint256 private constant KEEPER_FEE = 822;

  constructor()
    FlatMoneyV2PerpMarketTestSetup(FLATCOIN_VAULT, PERP_VIEWER, OptimismConfig.WBTC_CHAINLINK_ORACLE, KEEPER_FEE)
    OptimismSetup(FlatMoneyV2PerpMarketTestSharedData.FORK_BLOCK_NUMBER)
  {}

  function setUp() public override(FlatMoneyV2PerpMarketTestSetup, OptimismSetup) {
    super.setUp();
  }
}
