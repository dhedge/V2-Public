// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {SignedSafeMath} from "@openzeppelin/contracts/math/SignedSafeMath.sol";
import {SafeMath} from "@openzeppelin/contracts/math/SafeMath.sol";
import {IPyth} from "../../interfaces/pyth/IPyth.sol";
import {IGmxPrice} from "../../interfaces/gmx/IGmxPrice.sol";

library PythPriceLib {
  using SafeMath for uint256;
  using SignedSafeMath for int256;
  using SignedSafeMath for int64;

  uint256 internal constant DECIMALS = 8; // Pyth oracle price decimals

  struct OffchainOracle {
    bytes32 priceId; // Pyth network price Id
    uint32 maxAge; // Oldest price that is acceptable to use
    uint32 minConfidenceRatio; // the minimum Pyth oracle price / expo ratio. The higher, the more confident the accuracy of the price.
  }

  function getTokenMinMaxPrice(
    bool useMinMax,
    IPyth pythOracleContract,
    OffchainOracle memory oracleData
  ) internal view returns (IGmxPrice.Price memory priceMinMax) {
    (uint256 price, , uint256 confidence) = getOffchainPrice(pythOracleContract, oracleData);

    require(confidence != 0, "Offchain price invalid");

    if (useMinMax) {
      priceMinMax = IGmxPrice.Price({min: price.sub(confidence), max: price.add(confidence)});
    } else {
      priceMinMax = IGmxPrice.Price({min: price, max: price});
    }
  }

  /// @notice Fetches the price of collateral from Pyth network price feed.
  /// @return price The latest price of asset, in decimals of (-expo).
  /// @return timestamp The timestamp of the latest price.
  function getOffchainPrice(
    IPyth pythOracleContract,
    OffchainOracle memory oracleData
  ) internal view returns (uint256 price, uint256 timestamp, uint256 confidence) {
    require(address(pythOracleContract) != address(0), "Offchain oracle zero address");
    IPyth.Price memory priceData = pythOracleContract.getPriceNoOlderThan(oracleData.priceId, oracleData.maxAge);
    // Check that Pyth price and confidence is a positive value
    require(
      priceData.price > 0 && priceData.conf > 0 && abs(int256(priceData.expo)) == DECIMALS,
      "Invalid Pyth oracle data"
    );
    // Check that Pyth price confidence meets minimum
    require(
      priceData.price.div(int64(priceData.conf)) >= int32(oracleData.minConfidenceRatio),
      "Pyth price confidence too low"
    );
    timestamp = priceData.publishTime;
    price = (uint256(priceData.price));

    confidence = uint256(priceData.conf);
  }

  /// @dev Returns the absolute unsigned value of a signed value.
  function abs(int256 n) internal pure returns (uint256) {
    // must be unchecked in order to support `n = type(int256).min`
    return uint256(n >= 0 ? n : -n);
  }
}
