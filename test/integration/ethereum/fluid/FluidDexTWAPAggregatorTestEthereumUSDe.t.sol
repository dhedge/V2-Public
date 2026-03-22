// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {FluidDexTWAPAggregatorTestSetup} from "test/integration/common/fluid/FluidDexTWAPAggregatorTestSetup.t.sol";
import {IAggregatorV3Interface} from "contracts/interfaces/IAggregatorV3Interface.sol";
import {IFluidDexT1} from "contracts/interfaces/fluid/IFluidDexT1.sol";
import {EthereumConfig} from "test/integration/utils/foundry/config/EthereumConfig.sol";

contract FluidDexTWAPAggregatorTestEthereumUSDe is FluidDexTWAPAggregatorTestSetup {
  // TWAP period: 22 minutes - maximum that works with available oracle data at fork block.
  uint256 private constant TWAP_PERIOD = 1320;
  // Maximum deviation: 1 bps = 0.01%
  uint256 private constant MAX_DEVIATION = 1;

  constructor()
    FluidDexTWAPAggregatorTestSetup(
      IFluidDexT1(EthereumConfig.FLUID_DEX_USDe_USDT_POOL),
      EthereumConfig.USDe,
      IAggregatorV3Interface(EthereumConfig.USDT_CHAINLINK_ORACLE),
      TWAP_PERIOD,
      IAggregatorV3Interface(0xcD892744e99D2B617fe6D7fa109A73d786F5CE8C), // Existing UniV3 TWAP
      MAX_DEVIATION
    )
  {}

  function setUp() public override {
    vm.createSelectFork("ethereum", 24313660);

    super.setUp();
  }
}
