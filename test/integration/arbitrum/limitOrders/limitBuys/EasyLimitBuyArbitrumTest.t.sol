// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {EasyLimitBuyTestSetup} from "test/integration/common/limitOrders/limitBuys/EasyLimitBuyTestSetup.t.sol";
import {ArbitrumConfig} from "test/integration/utils/foundry/config/ArbitrumConfig.sol";

/// @notice EasyLimitBuyManager tests on Arbitrum fork
contract EasyLimitBuyArbitrumTest is EasyLimitBuyTestSetup {
  uint256 public constant FORK_BLOCK_NUMBER = 440946154;

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
    vm.createSelectFork("arbitrum", FORK_BLOCK_NUMBER);
    super.setUp();
  }
}
