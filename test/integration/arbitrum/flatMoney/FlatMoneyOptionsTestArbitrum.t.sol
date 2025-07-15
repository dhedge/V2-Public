// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma abicoder v2;

import {ArbitrumConfig} from "test/integration/utils/foundry/config/ArbitrumConfig.sol";
import {FlatMoneyOptionsTestSharedData} from "test/integration/arbitrum/flatMoney/FlatMoneyOptionsTestSharedData.sol";
import {FlatMoneyOptionsTestSetup} from "test/integration/common/flatMoney/FlatMoneyOptionsTestSetup.t.sol";
import {ArbitrumSetup} from "test/integration/utils/foundry/chains/ArbitrumSetup.t.sol";

contract FlatMoneyOptionsTestArbitrum is FlatMoneyOptionsTestSetup, ArbitrumSetup {
  address private constant FLATCOIN_VAULT = 0x29fAD9d44C550e5D8081AB35763797B39d75b858;
  address private constant COLLATERAL_ASSET_PRICE_FEED = 0x092e0dA71bbbF4f32749719ac3f42B294ebeCc3d;
  address private constant WHITELISTED_POOL_LOGIC = 0x32c99f405069eF47CEBc0db9F4FD6e9eDe2244b1;
  uint256 private constant KEEPER_FEE = 173;

  constructor()
    FlatMoneyOptionsTestSetup(
      FLATCOIN_VAULT,
      COLLATERAL_ASSET_PRICE_FEED,
      ArbitrumConfig.POOL_FACTORY_PROD,
      ArbitrumConfig.NFT_TRACKER_PROD,
      WHITELISTED_POOL_LOGIC,
      KEEPER_FEE
    )
    ArbitrumSetup(FlatMoneyOptionsTestSharedData.FORK_BLOCK_NUMBER)
  {}

  function setUp() public override(FlatMoneyOptionsTestSetup, ArbitrumSetup) {
    super.setUp();
  }
}
