// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

// solhint-disable-next-line max-line-length
import {ChainlinkPythPriceAggregatorTestSetup} from "test/integration/common/priceAggregators/ChainlinkPythPriceAggregatorTestSetup.t.sol";
import {ArbitrumConfig} from "test/integration/utils/foundry/config/ArbitrumConfig.sol";

contract ChainlinkPythPriceAggregatorTestArbitrum is ChainlinkPythPriceAggregatorTestSetup {
  /// @dev WETH's configuration from `config/arbitrum/dHEDGE Assets list.json`.

  constructor()
    ChainlinkPythPriceAggregatorTestSetup(
      ArbitrumConfig.WETH,
      ArbitrumConfig.PYTH_PRICE_FEED_CONTRACT,
      ArbitrumConfig.WETH_CHAINLINK_ORACLE,
      90_000,
      ArbitrumConfig.PYTH_ETH_PRICE_ID
    )
  {}

  function setUp() public override {
    vm.createSelectFork("arbitrum", 489036888);

    super.setUp();
  }
}
