// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {PoolLimitOrderManagerTestSetup} from "test/integration/common/limitOrders/PoolLimitOrderManagerTestSetup.t.sol";
import {ArbitrumConfig} from "test/integration/utils/foundry/config/ArbitrumConfig.sol";

contract PoolLimitOrderManagerArbitrum is PoolLimitOrderManagerTestSetup {
  uint256 public constant FORK_BLOCK_NUMBER = 307749323;

  constructor()
    PoolLimitOrderManagerTestSetup(
      ArbitrumConfig.WETH,
      ArbitrumConfig.WETH,
      ArbitrumConfig.SWAPPER,
      ArbitrumConfig.POOL_FACTORY_PROD,
      ArbitrumConfig.USDC,
      ArbitrumConfig.BTCBULL3X,
      ArbitrumConfig.ETHBULL3X,
      ArbitrumConfig.WBTC,
      ArbitrumConfig.WBTC_CHAINLINK_ORACLE
    )
  {}

  function setUp() public override {
    vm.createSelectFork("arbitrum", FORK_BLOCK_NUMBER);

    super.setUp();
  }
}
