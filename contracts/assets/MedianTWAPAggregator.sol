// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.7.6;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/math/SignedSafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@uniswap/lib/contracts/libraries/FixedPoint.sol";

import "../interfaces/IAggregatorV3Interface.sol";
import "../interfaces/uniswapv2/IUniswapV2Pair.sol";
import "../interfaces/IERC20Extended.sol";
import "../utils/uniswap/UniswapV2OracleLibrary.sol";
import "../utils/DhedgeMath.sol";

/**
 * @title Median TWAP USD price aggregator.
 * @notice Convert ETH denominated oracles to to USD denominated oracle
 * @dev This should have `latestRoundData` function as chainlink pricing oracle.
 */
contract MedianTWAPAggregator is Ownable, Pausable, IAggregatorV3Interface {
  using SafeERC20 for IERC20;
  using SignedSafeMath for int256;
  using SafeMath for uint256;
  using DhedgeMath for uint256;
  using FixedPoint for *;

  IUniswapV2Pair public immutable pair;
  address public immutable mainToken;
  IAggregatorV3Interface public immutable otherTokenUsdAggregator;
  uint256 public mainTokenDecimals;
  uint256 public otherTokenDecimals;

  uint256 public priceCumulativeLast;
  uint32 public blockTimestampLast;

  mapping(uint256 => int256) public twaps;
  uint256 public twapLastIndex;

  uint256 public updateInterval;

  uint256 public maxGasPrice = 200 gwei;
  uint256 public maxGasUsed = 130000; //130K

  // solhint-disable-next-line no-empty-blocks
  receive() external payable {}

  // solhint-disable-next-line no-empty-blocks
  fallback() external payable {}

  constructor(
    IUniswapV2Pair _pair,
    address _mainToken, // DHT
    IAggregatorV3Interface _otherTokenUsdAggregator, // WETH price aggregator
    uint256 _updateInterval
  ) Ownable() Pausable() {
    pair = _pair;
    mainToken = _mainToken;
    otherTokenUsdAggregator = _otherTokenUsdAggregator;
    updateInterval = _updateInterval;

    mainTokenDecimals = IERC20Extended(_mainToken).decimals();
    if (_mainToken == _pair.token0()) {
      priceCumulativeLast = _pair.price0CumulativeLast();
      otherTokenDecimals = IERC20Extended(_pair.token1()).decimals();
    } else {
      priceCumulativeLast = _pair.price1CumulativeLast();
      otherTokenDecimals = IERC20Extended(_pair.token0()).decimals();
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

  function update() external {
    _update();
  }

  function updateWithIncentive() external {
    _update();

    uint256 gasPrice = tx.gasprice;
    uint256 cost = maxGasUsed.mul(maxGasPrice > gasPrice ? gasPrice : maxGasPrice);
    uint256 reward = uint256(cost.sqrt()).div(10);

    // solhint-disable-next-line avoid-low-level-calls, avoid-call-value
    (bool sent, ) = msg.sender.call{value: cost.add(reward)}("");
    require(sent, "failed to send incentive");
  }

  function _update() internal whenNotPaused {
    (uint256 price0Cumulative, uint256 price1Cumulative, uint32 blockTimestamp) = UniswapV2OracleLibrary
      .currentCumulativePrices(address(pair));
    uint32 timeElapsed = blockTimestamp - blockTimestampLast; // overflow is desired

    // ensure that at least one full period has passed since the last update
    require(timeElapsed >= updateInterval, "period is not passed");

    uint256 priceCumulative = mainToken == pair.token0() ? price0Cumulative : price1Cumulative;
    // overflow is desired, casting never truncates
    // cumulative price is in (uq112x112 price * seconds) units so we simply wrap it after division by time elapsed
    twapLastIndex++;
    twaps[twapLastIndex] = (FixedPoint.uq112x112(uint224((priceCumulative - priceCumulativeLast) / timeElapsed)))
      .mul(10**mainTokenDecimals)
      .decode144();

    priceCumulativeLast = priceCumulative;
    blockTimestampLast = blockTimestamp;
  }

  function consult() public view whenNotPaused returns (int256 price) {
    require(twapLastIndex > 3, "not enough twaps");

    if (twaps[twapLastIndex - 2] <= twaps[twapLastIndex - 1]) {
      if (twaps[twapLastIndex - 1] <= twaps[twapLastIndex]) {
        return twaps[twapLastIndex - 1];
      }
      if (twaps[twapLastIndex] <= twaps[twapLastIndex - 2]) {
        return twaps[twapLastIndex - 2];
      }
      return twaps[twapLastIndex];
    } else {
      if (twaps[twapLastIndex - 1] > twaps[twapLastIndex]) {
        return twaps[twapLastIndex - 1];
      }
      if (twaps[twapLastIndex] > twaps[twapLastIndex - 2]) {
        return twaps[twapLastIndex - 2];
      }
      return twaps[twapLastIndex];
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
    updatedAt = updatedAt1 > updatedAt2 ? updatedAt2 : updatedAt1;

    require(updatedAt.add(updateInterval.mul(12)) > block.timestamp, "price expired");

    if (otherTokenDecimals < 8) {
      answer = consult().mul(usdPrice).mul(int256(10**(8 - otherTokenDecimals))).div(
        int256(10**otherTokenUsdAggregator.decimals())
      );
    } else {
      answer = consult().mul(usdPrice).div(int256(10**(otherTokenDecimals - 8))).div(
        int256(10**otherTokenUsdAggregator.decimals())
      );
    }

    return (0, answer, 0, updatedAt, 0);
  }
}
