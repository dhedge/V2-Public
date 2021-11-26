// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.7.6;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/math/SignedSafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@uniswap/lib/contracts/libraries/FixedPoint.sol";

import "../interfaces/IAggregatorV3Interface.sol";
import "../interfaces/uniswapv2/IUniswapV2Pair.sol";
import "../utils/uniswap/UniswapV2OracleLibrary.sol";

/**
 * @title Median TWAP USD price aggregator.
 * @notice Convert ETH denominated oracles to to USD denominated oracle
 * @dev This should have `latestRoundData` function as chainlink pricing oracle.
 */
contract MedianTWAPAggregator is Ownable, Pausable, IAggregatorV3Interface {
  using SafeERC20 for IERC20;
  using SignedSafeMath for int256;
  using FixedPoint for *;

  IUniswapV2Pair public immutable pair;
  address public immutable mainToken;
  IAggregatorV3Interface public immutable otherTokenUsdAggregator;

  uint256 public priceCumulativeLast;
  uint32 public blockTimestampLast;

  mapping(uint256 => int256) public twaps;
  uint256 public twapLastIndex;

  IERC20 public rewardToken;
  uint256 public updateRewardAmount;
  uint256 public updateInterval;

  constructor(
    IUniswapV2Pair _pair,
    address _mainToken, // DHT
    IAggregatorV3Interface _otherTokenUsdAggregator, // WETH price aggregator
    uint256 _updateInterval,
    address _rewardToken,
    uint256 _updateRewardAmount
  ) Ownable() Pausable() {
    pair = _pair;
    mainToken = _mainToken;
    otherTokenUsdAggregator = _otherTokenUsdAggregator;
    updateInterval = _updateInterval;
    rewardToken = IERC20(_rewardToken);
    updateRewardAmount = _updateRewardAmount;

    if (_mainToken == _pair.token0()) {
      priceCumulativeLast = _pair.price0CumulativeLast();
    } else {
      priceCumulativeLast = _pair.price1CumulativeLast();
    }
  }

  function pause() external onlyOwner {
    _pause();
  }

  function unpause() external onlyOwner {
    _unpause();
  }

  function decimals() external pure override returns (uint8) {
    return 8;
  }

  function setUpdateInterval(uint256 _updateInterval) external onlyOwner {
    updateInterval = _updateInterval;
  }

  function setUpdateRewards(address _rewardToken, uint256 _updateRewardAmount) external onlyOwner {
    rewardToken = IERC20(_rewardToken);
    updateRewardAmount = _updateRewardAmount;
  }

  function update() external whenNotPaused {
    (uint256 price0Cumulative, uint256 price1Cumulative, uint32 blockTimestamp) = UniswapV2OracleLibrary
      .currentCumulativePrices(address(pair));
    uint32 timeElapsed = blockTimestamp - blockTimestampLast; // overflow is desired

    // ensure that at least one full period has passed since the last update
    require(timeElapsed >= updateInterval, "period is not passed");

    uint256 priceCumulative = mainToken == pair.token0() ? price0Cumulative : price1Cumulative;
    // overflow is desired, casting never truncates
    // cumulative price is in (uq112x112 price * seconds) units so we simply wrap it after division by time elapsed
    twaps[twapLastIndex] = (FixedPoint.uq112x112(uint224((priceCumulative - priceCumulativeLast) / timeElapsed)))
      .mul(10**18)
      .decode144();
    twapLastIndex++;

    priceCumulativeLast = priceCumulative;
    blockTimestampLast = blockTimestamp;

    uint256 rewards = (timeElapsed * updateRewardAmount) / updateInterval;
    uint256 remaining = rewardToken.balanceOf(address(this));
    rewards = rewards > remaining ? remaining : rewards;
    if (rewards > 0) {
      rewardToken.safeTransfer(msg.sender, rewards);
    }
  }

  function consult() public view whenNotPaused returns (int256 price) {
    require(twapLastIndex >= 3, "not enough twaps");

    if (twaps[twapLastIndex - 3] <= twaps[twapLastIndex - 2]) {
      if (twaps[twapLastIndex - 2] <= twaps[twapLastIndex - 1]) {
        return twaps[twapLastIndex - 2];
      }
      if (twaps[twapLastIndex - 1] <= twaps[twapLastIndex - 3]) {
        return twaps[twapLastIndex - 3];
      }
      return twaps[twapLastIndex - 1];
    } else {
      if (twaps[twapLastIndex - 2] > twaps[twapLastIndex - 1]) {
        return twaps[twapLastIndex - 2];
      }
      if (twaps[twapLastIndex - 1] > twaps[twapLastIndex - 3]) {
        return twaps[twapLastIndex - 3];
      }
      return twaps[twapLastIndex - 1];
    }
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
    whenNotPaused
    returns (
      uint80 roundId,
      int256 answer,
      uint256 startedAt,
      uint256 updatedAt,
      uint80 answeredInRound
    )
  {
    uint256 updatedAt1 = blockTimestampLast;
    (, int256 usdPrice, , uint256 updatedAt2, ) = otherTokenUsdAggregator.latestRoundData();
    answer = consult().mul(usdPrice).div(10**10).div(int256(10**otherTokenUsdAggregator.decimals()));

    return (0, answer, 0, updatedAt1 > updatedAt2 ? updatedAt2 : updatedAt1, 0);
  }
}
