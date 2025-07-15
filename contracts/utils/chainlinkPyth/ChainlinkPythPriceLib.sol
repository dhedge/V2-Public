// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {SignedSafeMath} from "@openzeppelin/contracts/math/SignedSafeMath.sol";
import {SafeMath} from "@openzeppelin/contracts/math/SafeMath.sol";
import {IPyth} from "../../interfaces/pyth/IPyth.sol";
import {IGmxPrice} from "../../interfaces/gmx/IGmxPrice.sol";
import {IAggregatorV3Interface as IChainlinkAggregatorV3} from "../../interfaces/IAggregatorV3Interface.sol";
import {PythPriceLib} from "../pyth/PythPriceLib.sol";

library ChainlinkPythPriceLib {
  using SafeMath for uint256;
  using SignedSafeMath for int256;
  using SignedSafeMath for int64;
  /// Chainlink oracle
  struct OnchainOracle {
    IChainlinkAggregatorV3 oracleContract; // Chainlink oracle contract
    uint32 maxAge; // Oldest price that is acceptable to use
  }

  struct OracleData {
    OnchainOracle onchainOracle; // Chainlink oracle data
    PythPriceLib.OffchainOracle offchainOracle; // Pyth oracle data
  }

  /// @notice Fetches the price of collateral from Chainlink oracle.
  /// @dev Will revert on any issue. This is because the Onchain price is critical
  /// @dev Mind the Chainlink oracle price decimals if switching to ETH pair (18 decimals)
  /// @return price The latest 18 decimal price of asset.
  /// @return timestamp The timestamp of the latest price.
  function getOnchainPrice(
    OracleData memory oracleData,
    uint256 onChainOracleDecimalsAdjustmentFactor
  ) internal view returns (uint256 price, uint256 timestamp) {
    IChainlinkAggregatorV3 oracle = oracleData.onchainOracle.oracleContract;
    if (address(oracle) == address(0)) revert("Onchain oracle zero address");

    (, int256 _price, , uint256 updatedAt, ) = oracle.latestRoundData();
    timestamp = updatedAt;
    // check Chainlink oracle price updated within `maxAge` time.
    require(block.timestamp <= timestamp.add(oracleData.onchainOracle.maxAge), "Onchain oracle price is stale");

    // Issue with onchain oracle indicates a serious problem
    require(_price > 0, "Onchain oracle price is invalid");
    price = uint256(_price).mul(onChainOracleDecimalsAdjustmentFactor); // convert Chainlink oracle decimals to 18
  }

  /// @notice Fetches the price of collateral from Pyth network price feed.
  /// @dev `_getPrice` can fall back to the Onchain oracle.
  /// @return price The latest 18 decimal price of asset.
  /// @return timestamp The timestamp of the latest price.
  /// @return invalid True if the price is invalid.
  /// @return confidence The 18 decimal USD price +- confidence interval
  function getOffchainPrice(
    OracleData memory oracleData,
    IPyth pythOracleContract
  ) internal view returns (uint256 price, uint256 timestamp, bool invalid, uint256 confidence) {
    require(address(pythOracleContract) != address(0), "Offchain oracle zero address");
    try
      pythOracleContract.getPriceNoOlderThan(oracleData.offchainOracle.priceId, oracleData.offchainOracle.maxAge)
    returns (IPyth.Price memory priceData) {
      timestamp = priceData.publishTime;

      // Check that Pyth price and confidence is a positive value
      // Check that the exponential param is negative (eg -8 for 8 decimals)
      if (priceData.price > 0 && priceData.conf > 0 && priceData.expo < 0 && priceData.expo > -19) {
        price = (uint256(priceData.price)).mul((10 ** uint256(18 + priceData.expo))); // convert oracle expo/decimals eg 8 -> 18

        // Check that Pyth price confidence meets minimum
        if (priceData.price.div(int64(priceData.conf)) < int32(oracleData.offchainOracle.minConfidenceRatio)) {
          invalid = true; // price confidence is too low
        } else {
          confidence = uint256(priceData.conf).mul(10 ** (uint256(18 + priceData.expo)));
        }
      } else {
        invalid = true;
      }
    } catch {
      invalid = true; // couldn't fetch the price with the asked input param
    }
  }

  /// @notice Returns the latest 18 decimal price of asset from either Pyth network or Chainlink.
  /// @dev It verifies the Pyth network price against Chainlink price (ensure that it is within a threshold).
  /// @return price The latest 18 decimal price of asset.
  /// @return timestamp The timestamp of the latest price.
  /// @return confidence The 18 decimal USD price +- confidence interval
  function getPrice(
    OracleData memory oracleData,
    IPyth pythOracleContract,
    uint256 onChainOracleDecimalsAdjustmentFactor
  ) internal view returns (uint256 price, uint256 timestamp, uint256 confidence) {
    (uint256 onchainPrice, uint256 onchainTime) = getOnchainPrice(oracleData, onChainOracleDecimalsAdjustmentFactor); // will revert if invalid
    (uint256 offchainPrice, uint256 offchainTime, bool offchainInvalid, uint256 offchainConfidence) = getOffchainPrice(
      oracleData,
      pythOracleContract
    );
    confidence = offchainConfidence;
    bool offchain;

    if (offchainInvalid == false) {
      // return the freshest price
      if (offchainTime >= onchainTime) {
        price = offchainPrice;
        timestamp = offchainTime;
        offchain = true;
      } else {
        price = onchainPrice;
        timestamp = onchainTime;
      }
    } else {
      price = onchainPrice;
      timestamp = onchainTime;
    }
  }

  /// @notice Get the min and max USD price of the asset.
  /// @dev Prices are in the same decimals as provided by the on-chain oracle (Chainlink), typically 8 decimals.
  /// @dev shouldn't assume always in 8 decimals
  /// @dev Used for GMX market integration
  function getTokenMinMaxPrice(
    bool useMinMax,
    IPyth pythOracleContract,
    OracleData memory oracleData,
    uint256 onChainOracleDecimalsAdjustmentFactor
  ) internal view returns (IGmxPrice.Price memory priceMinMax) {
    (uint256 price, , uint256 confidence) = getPrice(
      oracleData,
      pythOracleContract,
      onChainOracleDecimalsAdjustmentFactor
    );

    require(price > 0, "invalid priceMinMax");

    if (useMinMax) {
      priceMinMax = IGmxPrice.Price({
        min: price.sub(confidence).div(onChainOracleDecimalsAdjustmentFactor),
        max: price.add(confidence).div(onChainOracleDecimalsAdjustmentFactor)
      });
    } else {
      priceMinMax = IGmxPrice.Price({
        min: price.div(onChainOracleDecimalsAdjustmentFactor),
        max: price.div(onChainOracleDecimalsAdjustmentFactor)
      });
    }
  }
}
