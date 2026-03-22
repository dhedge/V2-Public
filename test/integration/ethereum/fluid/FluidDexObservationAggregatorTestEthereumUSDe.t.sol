// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {FluidDexObservationAggregatorTestSetup} from "test/integration/common/fluid/FluidDexObservationAggregatorTestSetup.t.sol";
import {IAggregatorV3Interface} from "contracts/interfaces/IAggregatorV3Interface.sol";
import {IFluidDexT1} from "contracts/interfaces/fluid/IFluidDexT1.sol";
import {EthereumConfig} from "test/integration/utils/foundry/config/EthereumConfig.sol";

/// @notice Tests FluidDexObservationAggregator with the USDe/USDT Fluid DEX pool
contract FluidDexObservationAggregatorTestEthereumUSDe is FluidDexObservationAggregatorTestSetup {
  uint256 private constant TWAP_PERIOD = 60 * 30; // 30 minutes
  uint256 private constant MIN_OBSERVATION_INTERVAL = 60 * 2; // 2 minutes
  uint256 private constant MAX_STALENESS = 60 * 5; // 5 minutes
  uint256 private constant VOLATILITY_LIMIT = 100; // 1% (100 bps)
  uint256 private constant BUFFER_SIZE = 64; // number of observations

  // Reference oracle: UniV3 TWAP for USDe
  address private constant USDe_UNIV3_TWAP_ORACLE = 0xcD892744e99D2B617fe6D7fa109A73d786F5CE8C;

  // Maximum acceptable deviation: less than 1 bps = 0%
  uint256 private constant MAX_DEVIATION = 0;

  constructor()
    FluidDexObservationAggregatorTestSetup(
      IFluidDexT1(EthereumConfig.FLUID_DEX_USDe_USDT_POOL),
      EthereumConfig.USDe,
      IAggregatorV3Interface(EthereumConfig.USDT_CHAINLINK_ORACLE),
      TWAP_PERIOD,
      MIN_OBSERVATION_INTERVAL,
      MAX_STALENESS,
      VOLATILITY_LIMIT,
      BUFFER_SIZE,
      IAggregatorV3Interface(USDe_UNIV3_TWAP_ORACLE),
      MAX_DEVIATION
    )
  {}

  function setUp() public override {
    vm.createSelectFork("ethereum", 24376734);

    super.setUp();
  }
}
