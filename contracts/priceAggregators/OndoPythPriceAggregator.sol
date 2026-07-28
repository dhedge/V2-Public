// SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

import {SafeCast} from "@openzeppelin/v5/contracts/utils/math/SafeCast.sol";

import {IAggregatorV3Interface} from "../interfaces/IAggregatorV3Interface.sol";
import {ICommonErrors} from "../interfaces/ICommonErrors.sol";
import {IPyth} from "../interfaces/pyth/IPyth.sol";
import {IGMTokenManager} from "../interfaces/ondo/IGMTokenManager.sol";
import {IOndoSanityCheckOracle} from "../interfaces/ondo/IOndoSanityCheckOracle.sol";
import {ISyntheticSharesOracle} from "../interfaces/ondo/ISyntheticSharesOracle.sol";

/// @title Ondo asset price aggregator using multiple Pyth price feeds and Ondo sanity check oracle
/// @notice Picks the freshest valid Pyth price across multiple trading sessions (regular, overnight, pre/post-market),
///         applies the sValue multiplier, and compares against Ondo's on-chain sanity check oracle.
/// @dev `latestRoundData` returns the fresher price between the on-chain sanity check and the best Pyth feed.
contract OndoPythPriceAggregator is IAggregatorV3Interface, ICommonErrors {
  error NoPythPriceIds();
  error OndoMintingPaused();
  error OndoRedemptionsPaused();
  error OnchainOraclePriceInvalid();
  error OnchainOraclePriceStale();
  error PriceDeviationTooLarge();
  error OndoAssetPaused();
  error InvalidSValue();

  IPyth public immutable pythOracleContract;
  IGMTokenManager public immutable gmTokenManager;
  /// @dev sValues are only present for Chainlink-supported Ondo assets.
  ISyntheticSharesOracle public immutable sValueOracle;
  address public immutable ondoAsset;

  bytes32[] public pythPriceIds;
  uint64 public immutable onchainMaxAge;
  uint32 public immutable pythMaxAge;
  uint32 public immutable pythMinConfidenceRatio;

  uint8 private constant PRICE_DECIMALS = 8;
  uint256 private constant DECIMALS_ADJUSTMENT_FACTOR = 10 ** (18 - PRICE_DECIMALS);

  constructor(
    IPyth _pythOracleContract,
    IGMTokenManager _gmTokenManager,
    ISyntheticSharesOracle _sValueOracle,
    address _ondoAsset,
    bytes32[] memory _pythPriceIds,
    uint64 _onchainMaxAge,
    uint32 _pythMaxAge,
    uint32 _pythMinConfidenceRatio
  ) {
    if (address(_pythOracleContract) == address(0)) revert ZeroAddress("_pythOracleContract");
    if (address(_gmTokenManager) == address(0)) revert ZeroAddress("_gmTokenManager");
    if (address(_sValueOracle) == address(0)) revert ZeroAddress("_sValueOracle");
    if (_ondoAsset == address(0)) revert ZeroAddress("_ondoAsset");
    if (_pythPriceIds.length == 0) revert NoPythPriceIds();

    pythOracleContract = _pythOracleContract;
    gmTokenManager = _gmTokenManager;
    sValueOracle = _sValueOracle;
    ondoAsset = _ondoAsset;
    pythPriceIds = _pythPriceIds;
    onchainMaxAge = _onchainMaxAge;
    pythMaxAge = _pythMaxAge;
    pythMinConfidenceRatio = _pythMinConfidenceRatio;
  }

  function decimals() external pure override returns (uint8) {
    return PRICE_DECIMALS;
  }

  /// @notice Get the latest round data. Returns the fresher price between on-chain and off-chain oracles.
  /// @return roundId Always 0
  /// @return answer The price in 8 decimals
  /// @return startedAt Always 0
  /// @return updatedAt Timestamp of the fresher price
  /// @return answeredInRound Always 0
  function latestRoundData()
    external
    view
    override
    returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
  {
    if (gmTokenManager.gmTokenMintingPaused(ondoAsset)) revert OndoMintingPaused();
    if (gmTokenManager.gmTokenRedemptionsPaused(ondoAsset)) revert OndoRedemptionsPaused();

    (uint256 onchainPrice, uint256 onchainTime, uint16 allowedDeviationBps) = _getOnchainPrice();
    (uint256 offchainRawPrice, uint256 offchainTime, bool offchainInvalid) = _getFreshestOffchainPrice();

    if (!offchainInvalid) {
      uint256 offchainPrice = _applySValue(offchainRawPrice);

      uint256 deviation;
      uint256 minPrice;
      if (offchainPrice > onchainPrice) {
        deviation = offchainPrice - onchainPrice;
        minPrice = onchainPrice;
      } else {
        deviation = onchainPrice - offchainPrice;
        minPrice = offchainPrice;
      }
      if ((deviation * 10_000) / minPrice > allowedDeviationBps) revert PriceDeviationTooLarge();

      if (offchainTime >= onchainTime) {
        answer = int256(offchainPrice / DECIMALS_ADJUSTMENT_FACTOR);
        updatedAt = offchainTime;
      } else {
        answer = int256(onchainPrice / DECIMALS_ADJUSTMENT_FACTOR);
        updatedAt = onchainTime;
      }
    } else {
      answer = int256(onchainPrice / DECIMALS_ADJUSTMENT_FACTOR);
      updatedAt = onchainTime;
    }

    return (0, answer, 0, updatedAt, 0);
  }

  /// @notice Fetches the on-chain price from Ondo's sanity check oracle.
  /// @dev Reverts if the price is stale or invalid.
  /// @return price The price in 18 decimals (already includes sValue).
  /// @return timestamp The last updated timestamp.
  /// @return allowedDeviationBps The maximum allowed deviation between on-chain and off-chain prices.
  function _getOnchainPrice() internal view returns (uint256 price, uint256 timestamp, uint16 allowedDeviationBps) {
    IOndoSanityCheckOracle.PriceData memory data = gmTokenManager.sanityCheckOracle().prices(ondoAsset);

    if (data.price == 0) revert OnchainOraclePriceInvalid();
    if (block.timestamp > uint256(data.lastUpdated) + onchainMaxAge) revert OnchainOraclePriceStale();

    price = data.price;
    timestamp = uint256(data.lastUpdated);
    allowedDeviationBps = data.allowedDeviationBps;
  }

  /// @notice Iterates all Pyth price IDs and returns the freshest valid price.
  /// @dev Returns the raw stock price (without sValue) in 18 decimals.
  /// @return price The freshest valid price in 18 decimals.
  /// @return timestamp The publish time of the freshest price.
  /// @return invalid True if no valid price was found across all feeds.
  function _getFreshestOffchainPrice() internal view returns (uint256 price, uint256 timestamp, bool invalid) {
    uint256 freshestTime;
    uint256 freshestPrice;

    for (uint256 i = 0; i < pythPriceIds.length; i++) {
      try pythOracleContract.getPriceNoOlderThan(pythPriceIds[i], pythMaxAge) returns (IPyth.Price memory priceData) {
        if (priceData.price > 0 && priceData.conf > 0 && priceData.expo < 0 && priceData.expo > -19) {
          if (SafeCast.toUint256(priceData.price) / priceData.conf >= pythMinConfidenceRatio) {
            if (priceData.publishTime > freshestTime) {
              freshestTime = priceData.publishTime;
              freshestPrice = uint256(int256(priceData.price)) * (10 ** (uint256(int256(18 + priceData.expo))));
            }
          }
        }
        // solhint-disable-next-line no-empty-blocks
      } catch {
        // skip invalid/stale feeds
      }
    }

    if (freshestPrice == 0) {
      invalid = true;
    } else {
      price = freshestPrice;
      timestamp = freshestTime;
    }
  }

  /// @notice Applies the sValue multiplier to convert raw stock price to Ondo token price.
  /// @dev Reverts if the sValue oracle call reverts or returns a zero sValue, to prevent
  ///      silently pricing with an assumed 1e18 multiplier when the real multiplier is unknown.
  ///      If the asset is paused (corporate action), reverts to prevent stale pricing.
  /// @param rawPrice The raw stock price in 18 decimals from Pyth.
  /// @return The Ondo token price in 18 decimals.
  function _applySValue(uint256 rawPrice) internal view returns (uint256) {
    (uint128 sValue, bool paused) = sValueOracle.getSValue(ondoAsset);
    if (paused) revert OndoAssetPaused();
    if (sValue == 0) revert InvalidSValue();
    return (rawPrice * uint256(sValue)) / 1e18;
  }
}
