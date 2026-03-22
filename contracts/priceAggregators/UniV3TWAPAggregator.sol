//
//        __  __    __  ________  _______    ______   ________
//       /  |/  |  /  |/        |/       \  /      \ /        |
//   ____$$ |$$ |  $$ |$$$$$$$$/ $$$$$$$  |/$$$$$$  |$$$$$$$$/
//  /    $$ |$$ |__$$ |$$ |__    $$ |  $$ |$$ | _$$/ $$ |__
// /$$$$$$$ |$$    $$ |$$    |   $$ |  $$ |$$ |/    |$$    |
// $$ |  $$ |$$$$$$$$ |$$$$$/    $$ |  $$ |$$ |$$$$ |$$$$$/
// $$ \__$$ |$$ |  $$ |$$ |_____ $$ |__$$ |$$ \__$$ |$$ |_____
// $$    $$ |$$ |  $$ |$$       |$$    $$/ $$    $$/ $$       |
//  $$$$$$$/ $$/   $$/ $$$$$$$$/ $$$$$$$/   $$$$$$/  $$$$$$$$/
//
// dHEDGE DAO - https://dhedge.org
//
// Copyright (c) 2025 dHEDGE DAO
//
// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;

import {SafeMath} from "@openzeppelin/contracts/math/SafeMath.sol";
import {SignedSafeMath} from "@openzeppelin/contracts/math/SignedSafeMath.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {OracleLibrary} from "@uniswap/v3-periphery/contracts/libraries/OracleLibrary.sol";

import {IAggregatorV3Interface} from "../interfaces/IAggregatorV3Interface.sol";
import {IERC20Extended} from "../interfaces/IERC20Extended.sol";

/// @title Median TWAP USD price aggregator of a Uniswap V3 LP pool.
/// @dev This should have `latestRoundData` function as Chainlink pricing oracle.
contract UniV3TWAPAggregator is IAggregatorV3Interface {
  using SafeMath for uint256;
  using SignedSafeMath for int256;

  IUniswapV3Pool public immutable pool;
  address public immutable mainToken; // the token for which to get the TWAP price (eg DHT)
  address public immutable pairToken;
  IAggregatorV3Interface public immutable pairTokenUsdAggregator; // Chainlink USD aggregator of pairing token (eg WETH)
  uint256 public immutable mainTokenUnit; // 1 main token in wei
  uint256 public immutable pairTokenUnit; // 1 pair token in wei
  uint32 public immutable updateInterval; // minimum interval for updating oracle

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

    mainTokenUnit = 10 ** IERC20Extended(_mainToken).decimals();

    address _pairToken = _pool.token0();
    if (_mainToken == _pairToken) {
      _pairToken = _pool.token1();
    }
    pairToken = _pairToken;
    pairTokenUnit = 10 ** IERC20Extended(_pairToken).decimals();
  }

  function decimals() external pure override returns (uint8) {
    return 8;
  }

  function latestRoundData()
    external
    view
    override
    returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
  {
    // ::consult might revert if period is less than the oldest observation.
    // if that's the case, consider increasing observation capacity so the pool can retain a longer history.
    // to do so, call ::increaseObservationCardinalityNext(uint16) on the pool, for example 256 for a 30 minute TWAP on L1 should suffice.
    (int24 tick, ) = OracleLibrary.consult(address(pool), updateInterval);

    uint256 quoteAmount = OracleLibrary.getQuoteAtTick(tick, uint128(mainTokenUnit), mainToken, pairToken);

    int256 pairUsdPrice;
    (, pairUsdPrice, , updatedAt, ) = pairTokenUsdAggregator.latestRoundData();

    answer = pairUsdPrice.mul(int256(quoteAmount)).div(int256(pairTokenUnit));

    return (0, answer, 0, updatedAt, 0);
  }
}
