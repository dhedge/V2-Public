// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.7.6;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/math/SignedSafeMath.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-periphery/contracts/libraries/OracleLibrary.sol";

import "../interfaces/IAggregatorV3Interface.sol";
import "../interfaces/IERC20Extended.sol";

/// @title Median TWAP USD price aggregator of a Uniswap V3 LP pool.
/// @notice Convert ETH denominated oracles to to USD denominated oracle
/// @dev This should have `latestRoundData` function as Chainlink pricing oracle.
contract UniV3TWAPAggregator is IAggregatorV3Interface {
  using SafeMath for uint256;
  using SignedSafeMath for int256;

  IUniswapV3Pool public immutable pool;
  address public mainToken; // the token for which to get the TWAP price (eg DHT)
  address public pairToken;
  IAggregatorV3Interface public immutable pairTokenUsdAggregator; // Chainlink USD aggregator of pairing token (eg WETH)
  uint256 public mainTokenUnit; // 1 main token in wei
  uint256 public pairTokenUnit; // 1 pair token in wei
  uint32 public updateInterval; // minimum interval for updating oracle

  constructor(
    IUniswapV3Pool _pool,
    address _mainToken,
    IAggregatorV3Interface _pairTokenUsdAggregator,
    uint32 _updateInterval
  ) {
    pool = _pool;
    mainToken = _mainToken;
    pairTokenUsdAggregator = _pairTokenUsdAggregator;
    updateInterval = _updateInterval;

    mainTokenUnit = 10**IERC20Extended(_mainToken).decimals();

    pairToken = _pool.token0();
    if (_mainToken == pairToken) {
      pairToken = _pool.token1();
    }
    pairTokenUnit = 10**IERC20Extended(pairToken).decimals();
  }

  /* ========== VIEWS ========== */

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
    returns (
      uint80 roundId,
      int256 answer,
      uint256 startedAt,
      uint256 updatedAt,
      uint80 answeredInRound
    )
  {
    (int24 tick, ) = OracleLibrary.consult(address(pool), updateInterval);

    uint256 quoteAmount = OracleLibrary.getQuoteAtTick(tick, uint128(mainTokenUnit), mainToken, pairToken);

    (, int256 usdPrice, , uint256 updatedAt, ) = pairTokenUsdAggregator.latestRoundData(); // This price may only update on deviation

    answer = usdPrice.mul(int256(quoteAmount)).div(int256(pairTokenUnit));

    return (0, answer, 0, updatedAt, 0);
  }
}
