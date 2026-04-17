// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {EasyLimitBuyZapTestSetup} from "test/integration/common/limitOrders/limitBuys/EasyLimitBuyZapTestSetup.t.sol";
import {ArbitrumConfig} from "test/integration/utils/foundry/config/ArbitrumConfig.sol";

/// @notice EasyLimitBuyManager zap/FFI tests on Arbitrum fork
contract EasyLimitBuyZapArbitrumTestFFIArbitrum is EasyLimitBuyZapTestSetup {
  uint256 public constant FORK_BLOCK_NUMBER = 440947030;

  uint256 public constant WETH_ZAP_AMOUNT = 1 ether;

  constructor()
    EasyLimitBuyZapTestSetup(
      ArbitrumConfig.POOL_FACTORY_PROD,
      ArbitrumConfig.USDC,
      ArbitrumConfig.USDy, // accepts USDC deposits
      ArbitrumConfig.WBTC,
      ArbitrumConfig.EASY_SWAPPER_V2_PROD,
      ArbitrumConfig.WETH, // zapInputToken - not the deposit asset
      WETH_ZAP_AMOUNT,
      ArbitrumConfig.CHAIN_ID
    )
  {}

  function setUp() public override {
    vm.createSelectFork("arbitrum", FORK_BLOCK_NUMBER);
    super.setUp();
  }
}
