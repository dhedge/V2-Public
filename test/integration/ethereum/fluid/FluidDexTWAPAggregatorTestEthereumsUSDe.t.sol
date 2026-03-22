// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {FluidDexTWAPAggregatorTestSetup} from "test/integration/common/fluid/FluidDexTWAPAggregatorTestSetup.t.sol";
import {IAggregatorV3Interface} from "contracts/interfaces/IAggregatorV3Interface.sol";
import {IFluidDexT1} from "contracts/interfaces/fluid/IFluidDexT1.sol";
import {EthereumConfig} from "test/integration/utils/foundry/config/EthereumConfig.sol";

contract FluidDexTWAPAggregatorTestEthereumsUSDe is FluidDexTWAPAggregatorTestSetup {
  // TWAP period: 7 minutes - maximum that works with available oracle data at fork block.
  uint256 private constant TWAP_PERIOD = 420;
  // Maximum deviation: 1 bps = 0.01%
  uint256 private constant MAX_DEVIATION = 1;

  constructor()
    FluidDexTWAPAggregatorTestSetup(
      IFluidDexT1(EthereumConfig.FLUID_DEX_sUSDe_USDT_POOL),
      EthereumConfig.sUSDe,
      IAggregatorV3Interface(EthereumConfig.USDT_CHAINLINK_ORACLE),
      TWAP_PERIOD,
      IAggregatorV3Interface(0x0e5458C2A9A9cefcf8c8C4C5B633b492124584C0), // Existing UniV3 TWAP
      MAX_DEVIATION
    )
  {}

  function setUp() public override {
    vm.createSelectFork("ethereum", 24313660);

    super.setUp();
  }
}
