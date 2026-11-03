// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {EasyLimitBuyTestSetup} from "test/integration/common/limitOrders/limitBuys/EasyLimitBuyTestSetup.t.sol";
import {ArbitrumConfig} from "test/integration/utils/foundry/config/ArbitrumConfig.sol";
import {ForkBlocks} from "test/integration/utils/foundry/config/ForkBlocks.sol";

/// @notice EasyLimitBuyManager tests on Arbitrum fork
contract EasyLimitBuyArbitrumTest is EasyLimitBuyTestSetup {
  constructor()
    EasyLimitBuyTestSetup(
      ArbitrumConfig.POOL_FACTORY_PROD,
      ArbitrumConfig.USDC,
      ArbitrumConfig.USDy, // accepts USDC deposits
      ArbitrumConfig.WBTC,
      ArbitrumConfig.EASY_SWAPPER_V2_PROD
    )
  {}

  function setUp() public override {
    vm.createSelectFork("arbitrum", ForkBlocks.ARBITRUM);
    super.setUp();
  }
}
