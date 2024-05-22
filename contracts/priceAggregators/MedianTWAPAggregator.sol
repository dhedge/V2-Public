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
import "../interfaces/uniswapV2/IUniswapV2Pair.sol";
import "../interfaces/IERC20Extended.sol";
import "../utils/uniswap/UniswapV2OracleLibrary.sol";
import "../utils/DhedgeMath.sol";

/// @title Median TWAP USD price aggregator of a Uniswap V2 LP pool.
/// @notice Convert ETH denominated oracles to to USD denominated oracle
/// @dev This should have `latestRoundData` function as Chainlink pricing oracle.
contract MedianTWAPAggregator is Ownable, Pausable, IAggregatorV3Interface {
  using SafeERC20 for IERC20;
  using SignedSafeMath for int256;
  using SafeMath for uint256;
  using DhedgeMath for uint256;
  using FixedPoint for *;

  IUniswapV2Pair public immutable pair;
  address public immutable mainToken; // the token for which to get the TWAP price (eg DHT)
  IAggregatorV3Interface public immutable pairTokenUsdAggregator; // Chainlink USD aggregator of pairing token (eg WETH)
  uint256 public mainTokenDecimals;
  uint256 public pairTokenDecimals;

  uint256 public priceCumulativeLast;
  uint32 public blockTimestampLast;
  uint32 public volatilityTripLimit; // percent max acceptable volatility of TWAPs, at which point latestRoundData reverts

  mapping(uint256 => int256) public twaps;
  uint256 public twapLastIndex;

  uint256 public updateInterval; // minimum interval for updating oracle
  uint256 public maxGasPrice = 200 gwei; // Update with incentive max
  uint256 public maxGasUsed = 130000; // Update with incentive max

  event UpdateIntervalSet(uint256 updateInterval);
  event VolatilityTripLimitSet(uint32 volatilityTripLimit);
  event Withdraw(uint256 withdrawAmount);
  event Updated(address caller);
  event UpdatedWithIncentive(address caller, uint256 amount);

  // solhint-disable-next-line no-empty-blocks
  receive() external payable {}

  // solhint-disable-next-line no-empty-blocks
  fallback() external payable {}

  constructor(
    IUniswapV2Pair _pair,
    address _mainToken,
    IAggregatorV3Interface _pairTokenUsdAggregator,
    uint256 _updateInterval,
    uint32 _volatilityTripLimit
  ) Ownable() Pausable() {
    pair = _pair;
    mainToken = _mainToken;
    pairTokenUsdAggregator = _pairTokenUsdAggregator;
    updateInterval = _updateInterval;
    volatilityTripLimit = _volatilityTripLimit;

    mainTokenDecimals = IERC20Extended(_mainToken).decimals();
    if (_mainToken == _pair.token0()) {
      priceCumulativeLast = _pair.price0CumulativeLast();
      pairTokenDecimals = IERC20Extended(_pair.token1()).decimals();
    } else {
      priceCumulativeLast = _pair.price1CumulativeLast();
      pairTokenDecimals = IERC20Extended(_pair.token0()).decimals();
    }
  }

  /* ========== VIEWS ========== */

  function decimals() external pure override returns (uint8) {
    return 8;
  }

  /// @notice Gets the main token median TWAP price (priced in pair token)
  function consult() public view whenNotPaused returns (int256 price) {
    require(twapLastIndex > 3, "not enough twaps");

    if (twaps[twapLastIndex - 2] <= twaps[twapLastIndex - 1]) {
      if (twaps[twapLastIndex - 1] <= twaps[twapLastIndex]) {
        require(!highVolatility(twaps[twapLastIndex - 2], twaps[twapLastIndex]), "price volatility too high");
        return twaps[twapLastIndex - 1];
      }
      if (twaps[twapLastIndex] <= twaps[twapLastIndex - 2]) {
        require(!highVolatility(twaps[twapLastIndex], twaps[twapLastIndex - 1]), "price volatility too high");
        return twaps[twapLastIndex - 2];
      }
      require(!highVolatility(twaps[twapLastIndex - 1], twaps[twapLastIndex - 2]), "price volatility too high");
      return twaps[twapLastIndex];
    } else {
      if (twaps[twapLastIndex - 1] > twaps[twapLastIndex]) {
        require(!highVolatility(twaps[twapLastIndex], twaps[twapLastIndex - 2]), "price volatility too high");
        return twaps[twapLastIndex - 1];
      }
      if (twaps[twapLastIndex] > twaps[twapLastIndex - 2]) {
        require(!highVolatility(twaps[twapLastIndex], twaps[twapLastIndex - 1]), "price volatility too high");
        return twaps[twapLastIndex - 2];
      }
      require(!highVolatility(twaps[twapLastIndex - 1], twaps[twapLastIndex - 2]), "price volatility too high");
      return twaps[twapLastIndex];
    }
  }

  /// @notice Checks for high price volatility in the recent TWAPs
  function highVolatility(int256 twapA, int256 twapB) public view returns (bool volatilityHigh) {
    uint256 deviationPercent = abs(twapA - twapB).mul(100).div(uint256(twapA));

    if (deviationPercent >= volatilityTripLimit) {
      volatilityHigh = true;
    }
  }

  /// @dev Returns the absolute unsigned value of a signed value.
  function abs(int256 n) internal pure returns (uint256) {
    // must be unchecked in order to support `n = type(int256).min`
    return uint256(n >= 0 ? n : -n);
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
    whenNotPaused
    returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
  {
    uint256 updatedAt1 = blockTimestampLast;
    require(updatedAt1.add(updateInterval.mul(12)) > block.timestamp, "TWAP price expired");

    (, int256 usdPrice, , uint256 updatedAt2, ) = pairTokenUsdAggregator.latestRoundData(); // This price may only update on deviation
    updatedAt = updatedAt1 > updatedAt2 ? updatedAt2 : updatedAt1;

    if (pairTokenDecimals < 8) {
      answer = consult().mul(usdPrice).mul(int256(10 ** (8 - pairTokenDecimals))).div(
        int256(10 ** pairTokenUsdAggregator.decimals())
      );
    } else {
      answer = consult().mul(usdPrice).div(int256(10 ** (pairTokenDecimals - 8))).div(
        int256(10 ** pairTokenUsdAggregator.decimals())
      );
    }

    return (0, answer, 0, updatedAt, 0);
  }

  /* ========== MUTATIVE FUNCTIONS ========== */

  /* ---------- Only Owner ---------- */

  function pause() external onlyOwner {
    _pause();
  }

  function unpause() external onlyOwner {
    _unpause();
  }

  function setVolatilityTripLimit(uint32 _volatilityTripLimit) external onlyOwner {
    volatilityTripLimit = _volatilityTripLimit;
    emit VolatilityTripLimitSet(_volatilityTripLimit);
  }

  function setUpdateInterval(uint256 _updateInterval) external onlyOwner {
    updateInterval = _updateInterval;
    emit UpdateIntervalSet(_updateInterval);
  }

  /// @notice Withdraws any native token deposits to the owner
  function withdraw(uint256 amount) external onlyOwner {
    require(amount <= address(this).balance, "balance is too low");
    msg.sender.transfer(amount);
    emit Withdraw(amount);
  }

  /* ---------- Public ---------- */

  /// @notice Creates a new TWAP (update interval must pass first)
  function update() external {
    _update();

    emit Updated(msg.sender);
  }

  /// @notice Creates a new TWAP and gives caller a native token reward (update interval must pass first)
  function updateWithIncentive() external {
    _update();

    uint256 gasPrice = tx.gasprice;
    uint256 cost = maxGasUsed.mul(maxGasPrice > gasPrice ? gasPrice : maxGasPrice);
    uint256 reward = uint256(cost.sqrt()).div(10);
    uint256 totalReward = cost.add(reward);

    // solhint-disable-next-line avoid-low-level-calls, avoid-call-value
    (bool sent, ) = msg.sender.call{value: totalReward}("");
    require(sent, "failed to send incentive");

    emit UpdatedWithIncentive(msg.sender, totalReward);
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
      .mul(10 ** mainTokenDecimals)
      .decode144();

    priceCumulativeLast = priceCumulative;
    blockTimestampLast = blockTimestamp;
  }
}
