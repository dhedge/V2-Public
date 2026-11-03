// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {FluidDexTWAPAggregatorTestSetup} from "test/integration/common/fluid/FluidDexTWAPAggregatorTestSetup.t.sol";
import {IAggregatorV3Interface} from "contracts/interfaces/IAggregatorV3Interface.sol";
import {IFluidDexT1} from "contracts/interfaces/fluid/IFluidDexT1.sol";
import {EthereumConfig} from "test/integration/utils/foundry/config/EthereumConfig.sol";
import {ForkBlocks} from "test/integration/utils/foundry/config/ForkBlocks.sol";

contract FluidDexTWAPAggregatorTestEthereumsUSDe is FluidDexTWAPAggregatorTestSetup {
  // TWAP period: 7 minutes - maximum that works with available oracle data at fork block.
  uint256 private constant TWAP_PERIOD = 420;
  // Maximum deviation: 10 bps = 0.1%
  uint256 private constant MAX_DEVIATION = 10;

  constructor()
    FluidDexTWAPAggregatorTestSetup(
      IFluidDexT1(EthereumConfig.FLUID_DEX_sUSDe_USDT_POOL),
      EthereumConfig.sUSDe,
      IAggregatorV3Interface(EthereumConfig.USDT_CHAINLINK_ORACLE),
      TWAP_PERIOD,
      IAggregatorV3Interface(EthereumConfig.sUSDe_CHAINLINK_ORACLE), // reference oracle
      MAX_DEVIATION
    )
  {}

  function setUp() public override {
    vm.createSelectFork("ethereum", ForkBlocks.ETHEREUM);

    super.setUp();
  }
}
