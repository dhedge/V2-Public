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
// SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

import {IAggregatorV3Interface} from "../interfaces/IAggregatorV3Interface.sol";
import {ICommonErrors} from "../interfaces/ICommonErrors.sol";
import {IOracleHeartbeat} from "../interfaces/IOracleHeartbeat.sol";

/// @title Midas mToken price aggregator
/// @notice Thin passthrough wrapper over a Midas `CustomAggregatorV3CompatibleFeed` that adds a
///         dHEDGE `IOracleHeartbeat` so `AssetHandler` overrides its default 25h `chainlinkTimeout`.
/// @dev    Midas NAV feeds are pushed manually by a trusted feed admin roughly per business day, with
///         occasional multi-day gaps over weekends/holidays (observed max ~5 days). The default
///         chainlink timeout would false-revert and brick the pool, so a longer, explicit heartbeat
///         is required — mirroring the "Ondo ~2 day attestation oracle" case in `AssetHandler`.
///         The underlying feed already enforces min/max answer bounds and a per-update deviation cap
///         on write, so this wrapper adds no extra bounds — only staleness. A non-positive price is
///         already rejected downstream by the consuming `AssetHandler`, so no local check is needed.
contract MidasPriceAggregator is IAggregatorV3Interface, IOracleHeartbeat, ICommonErrors {
  /// @notice Thrown when the underlying feed does not report 8 decimals (AssetHandler assumes 8).
  error UnexpectedFeedDecimals(uint8 decimals);

  /// @notice Thrown when the configured heartbeat is zero.
  error ZeroHeartbeat();

  uint8 private constant PRICE_DECIMALS = 8;

  /// @notice The underlying Midas custom aggregator feed (mToken/USD, 8 decimals).
  IAggregatorV3Interface public immutable underlyingFeed;

  /// @notice Maximum acceptable age (seconds) of the underlying feed's latest update.
  uint256 public immutable heartbeat;

  /// @param _underlyingFeed The Midas custom aggregator feed to wrap (must report 8 decimals).
  /// @param _heartbeat Maximum acceptable staleness in seconds (e.g. 7 days for a ~daily NAV feed).
  constructor(IAggregatorV3Interface _underlyingFeed, uint256 _heartbeat) {
    if (address(_underlyingFeed) == address(0)) revert ZeroAddress("_underlyingFeed");
    if (_heartbeat == 0) revert ZeroHeartbeat();

    uint8 feedDecimals = _underlyingFeed.decimals();
    if (feedDecimals != PRICE_DECIMALS) revert UnexpectedFeedDecimals(feedDecimals);

    underlyingFeed = _underlyingFeed;
    heartbeat = _heartbeat;
  }

  /// @inheritdoc IAggregatorV3Interface
  function decimals() external pure override returns (uint8) {
    return PRICE_DECIMALS;
  }

  /// @notice Maximum acceptable age for the underlying feed's price update.
  /// @dev Read by `AssetHandler` to override its default `chainlinkTimeout` for this aggregator.
  function oracleHeartbeat() external view override returns (uint256) {
    return heartbeat;
  }

  /// @inheritdoc IAggregatorV3Interface
  /// @dev Passthrough of the underlying feed. Staleness is enforced by `AssetHandler` via
  ///      `oracleHeartbeat()`, and a non-positive price is rejected by `AssetHandler` itself.
  function latestRoundData()
    external
    view
    override
    returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
  {
    return underlyingFeed.latestRoundData();
  }
}
