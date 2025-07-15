// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.7.6;

import {SignedSafeMath} from "@openzeppelin/contracts/math/SignedSafeMath.sol";

import {IAggregatorV3Interface} from "../interfaces/IAggregatorV3Interface.sol";

/// @notice Oracle that combines two Chainlink aggregators to return a token price in USD.
/// @dev For example sUSDS / USDS -> USDS / USD
/// @dev This should have `latestRoundData` function as chainlink pricing oracle.
contract CustomCrossAggregator is IAggregatorV3Interface {
  using SignedSafeMath for int256;

  address public immutable token;
  IAggregatorV3Interface public immutable tokenToTokenAggregator;
  IAggregatorV3Interface public immutable tokenToUsdAggregator;
  uint8 public immutable tokenToTokenDecimals;
  uint8 public immutable tokenToUsdDecimals;

  constructor(
    address _token,
    IAggregatorV3Interface _tokenToTokenAggregator,
    IAggregatorV3Interface _tokenToUsdAggregator
  ) {
    uint8 _tokenToTokenDecimals = _tokenToTokenAggregator.decimals();
    uint8 _tokenToUsdDecimals = _tokenToUsdAggregator.decimals();

    require(_tokenToTokenDecimals > 0 && _tokenToUsdDecimals > 0, "CCA: Invalid decimals");

    token = _token;
    tokenToTokenAggregator = _tokenToTokenAggregator;
    tokenToUsdAggregator = _tokenToUsdAggregator;
    tokenToTokenDecimals = _tokenToTokenDecimals;
    tokenToUsdDecimals = _tokenToUsdDecimals;
  }

  function decimals() external pure override returns (uint8) {
    return 8;
  }

  /// @notice Get the latest round data. Should be the same format as chainlink aggregator.
  /// @return roundId The round ID.
  /// @return answer The price - the latest round data of USD (price decimal: 8)
  /// @return startedAt Timestamp of when the round started.
  /// @return updatedAt Timestamp of when the round was updated.
  /// @return answeredInRound The round ID of the round in which the answer was computed.
  function latestRoundData()
    external
    view
    override
    returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
  {
    (, int256 tokenToTokenPrice, , uint256 tokenToTokenUpdatedAt, ) = tokenToTokenAggregator.latestRoundData();
    (, int256 tokenToUsdPrice, , uint256 tokenToUsdUpdatedAt, ) = tokenToUsdAggregator.latestRoundData();

    // answer takes into account decimals of the tokenToToken and tokenToUsd aggregators
    answer = tokenToTokenPrice.mul(tokenToUsdPrice).div(int256(10 ** tokenToTokenDecimals));

    require(answer >= 1e4, "CCA: price too low"); // reverts on a critical rounding error

    answer = answer.mul(1e8).div(int256(10 ** tokenToUsdDecimals));

    return (0, answer, 0, tokenToTokenUpdatedAt > tokenToUsdUpdatedAt ? tokenToUsdUpdatedAt : tokenToTokenUpdatedAt, 0);
  }
}
