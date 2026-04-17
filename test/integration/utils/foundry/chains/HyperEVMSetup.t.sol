// SPDX-License-Identifier: MIT

pragma solidity >=0.7.6 <0.9.0;
pragma abicoder v2;

import {HyperEVMConfig} from "test/integration/utils/foundry/config/HyperEVMConfig.sol";
import {HyperliquidTestSetup} from "test/integration/hyperevm/test-suite/HyperliquidTestSetup.sol";

/// @title HyperEVM Chain Setup for Foundry tests
/// @notice Sets up the HyperEVM chain for integration testing
abstract contract HyperEVMSetup is HyperliquidTestSetup {
  uint256 public constant forkBlockNumber = 25342036;

  function setUp() public virtual override {
    vm.createSelectFork("hyperevm", forkBlockNumber);

    // Mock the USDC/USD Chainlink price feed to always return exactly $1
    // This ensures deterministic test results regardless of actual market price
    _mockUSDCPriceFeed();

    super.setUp();
  }

  function _mockUSDCPriceFeed() internal {
    // Mock latestRoundData to return $1.00
    vm.mockCall(
      HyperEVMConfig.USDC_USD_PRICE_FEED,
      abi.encodeWithSignature("latestRoundData()"),
      abi.encode(
        uint80(1), // roundId
        int256(1e8), // answer: $1.00 with 8 decimals
        uint256(block.timestamp), // startedAt
        uint256(block.timestamp), // updatedAt
        uint80(1) // answeredInRound
      )
    );
    // Mock decimals to return 8
    vm.mockCall(HyperEVMConfig.USDC_USD_PRICE_FEED, abi.encodeWithSignature("decimals()"), abi.encode(uint8(8)));
  }
}
