// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.7.6;

import "@openzeppelin/contracts/math/SignedSafeMath.sol";

import "../interfaces/IAggregatorV3Interface.sol";

/**
 * @title USD price aggregator.
 * @notice Convert ETH denominated oracles to to USD denominated oracle
 * @dev This should have `latestRoundData` function as chainlink pricing oracle.
 */
contract ETHCrossAggregator is IAggregatorV3Interface {
  using SignedSafeMath for int256;

  address public token;
  address public tokenEthAggregator;
  address public ethUsdAggregator;

  constructor(
    address _token,
    address _tokenEthAggregator,
    address _ethUsdAggregator
  ) {
    token = _token;
    tokenEthAggregator = _tokenEthAggregator;
    ethUsdAggregator = _ethUsdAggregator;
  }

  function decimals() external pure override returns (uint8) {
    return 8;
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
    (, int256 tokenEthPrice, , uint256 updatedAt1, ) = IAggregatorV3Interface(tokenEthAggregator).latestRoundData();
    (, int256 ethUsdPrice, , uint256 updatedAt2, ) = IAggregatorV3Interface(ethUsdAggregator).latestRoundData();

    answer = tokenEthPrice.mul(ethUsdPrice).div(1e18);
    return (0, answer, 0, updatedAt1 > updatedAt2 ? updatedAt2 : updatedAt1, 0);
  }
}
