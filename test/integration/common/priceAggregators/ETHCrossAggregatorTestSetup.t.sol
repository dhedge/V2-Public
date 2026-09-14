// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {Test} from "forge-std/Test.sol";

import {IAggregatorV3Interface} from "contracts/interfaces/IAggregatorV3Interface.sol";

/// @notice `ETHCrossAggregator` prices tokens that only have an ETH-denominated Chainlink feed by
/// crossing it with the ETH/USD feed.
abstract contract ETHCrossAggregatorTestSetup is Test {
  address internal immutable token;
  address internal immutable tokenEthFeed;
  address internal immutable ethUsdFeed;

  IAggregatorV3Interface internal aggregator;

  constructor(address _token, address _tokenEthFeed, address _ethUsdFeed) {
    token = _token;
    tokenEthFeed = _tokenEthFeed;
    ethUsdFeed = _ethUsdFeed;
  }

  function setUp() public virtual {
    aggregator = IAggregatorV3Interface(
      deployCode("ETHCrossAggregator.sol:ETHCrossAggregator", abi.encode(token, tokenEthFeed, ethUsdFeed))
    );
  }

  function test_aggregator_reports_eight_decimals() public view {
    assertEq(uint256(aggregator.decimals()), 8);
  }

  function test_aggregator_crosses_token_eth_price_with_eth_usd_price() public view {
    (, int256 tokenEthPrice, , , ) = IAggregatorV3Interface(tokenEthFeed).latestRoundData();
    (, int256 ethUsdPrice, , , ) = IAggregatorV3Interface(ethUsdFeed).latestRoundData();
    (, int256 tokenUsdPrice, , , ) = aggregator.latestRoundData();

    assertGt(tokenUsdPrice, 0);
    // The token/ETH feed carries 18 decimals, so crossing it leaves the ETH/USD feed's 8.
    assertEq(tokenUsdPrice, (ethUsdPrice * tokenEthPrice) / 1e18);
  }
}
