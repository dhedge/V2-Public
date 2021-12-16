// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.7.6;

import "@openzeppelin/contracts/math/SignedSafeMath.sol";

import "../interfaces/IAggregatorV3Interface.sol";

/**
 * @title Chainlink Cross price aggregator.
 * @notice Convert Susd priced assets into usd priced assets
 * @dev This should have `latestRoundData` function as chainlink pricing oracle.
 */
contract SynthPriceAggregator is IAggregatorV3Interface {
  using SignedSafeMath for int256;

  // i.e sUSD chainlink Oracle
  address public susdPriceAggregator;
  // i.e Eth chainlink Oracle
  address public tokenPriceAggregator;

  constructor(address _susdPriceAggregator, address _tokenPriceAggregator) {
    susdPriceAggregator = _susdPriceAggregator;
    tokenPriceAggregator = _tokenPriceAggregator;
  }

  /**
   * @notice Get the latest round data. Should be the same format as chainlink aggregator.
   * @return roundId The round ID.
   * @return answer The price - the latest round data of USD (price decimal: 8)
   * @return startedAt Timestamp of when the round started.
   * @return updatedAt Timestamp of when the round was updated.
   * @return answeredInRound The round ID of the round in which the answer was computed.
   */
  function latestRoundData()
    external
    view
    override
    returns (
      uint80 roundId,
      int256 answer,
      uint256 startedAt,
      uint256 updatedAt,
      uint80 answeredInRound
    )
  {
    (, int256 sUSDUsdPrice, , uint256 updatedAt1, ) = IAggregatorV3Interface(susdPriceAggregator).latestRoundData();
    (, int256 tokenUsdPrice, , uint256 updatedAt2, ) = IAggregatorV3Interface(tokenPriceAggregator).latestRoundData();

    answer = sUSDUsdPrice.mul(tokenUsdPrice).div(1e8);
    return (0, answer, 0, updatedAt1 > updatedAt2 ? updatedAt2 : updatedAt1, 0);
  }

  function decimals() external pure override returns (uint8) {
    return 8;
  }
}
