// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {ETHCrossAggregatorTestSetup} from "test/integration/common/priceAggregators/ETHCrossAggregatorTestSetup.t.sol";
import {ArbitrumConfig} from "test/integration/utils/foundry/config/ArbitrumConfig.sol";

contract ETHCrossAggregatorTestArbitrum is ETHCrossAggregatorTestSetup {
  /// @dev wstETH is priced through its wstETH/ETH feed crossed with ETH/USD, as configured in
  /// `config/arbitrum/dHEDGE Assets list.json`.
  address private constant WSTETH_ETH_ORACLE = 0xb523AE262D20A936BC152e6023996e46FDC2A95D;

  constructor()
    ETHCrossAggregatorTestSetup(ArbitrumConfig.WSTETH, WSTETH_ETH_ORACLE, ArbitrumConfig.WETH_CHAINLINK_ORACLE)
  {}

  function setUp() public override {
    vm.createSelectFork("arbitrum", 489036888);

    super.setUp();
  }
}
