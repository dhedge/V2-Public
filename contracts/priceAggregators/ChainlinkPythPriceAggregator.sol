// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma abicoder v2;

import {SignedSafeMath} from "@openzeppelin/contracts/math/SignedSafeMath.sol";
import {SafeMath} from "@openzeppelin/contracts/math/SafeMath.sol";

import {IAggregatorV3Interface as IChainlinkAggregatorV3} from "../interfaces/IAggregatorV3Interface.sol";
import {IPyth} from "../interfaces/pyth/IPyth.sol";
import {IGmxPrice} from "../interfaces/gmx/IGmxPrice.sol";
import {IGmxCustomPriceFeedProvider} from "../interfaces/gmx/IGmxCustomPriceFeedProvider.sol";
import {ChainlinkPythPriceLib} from "../utils/chainlinkPyth/ChainlinkPythPriceLib.sol";

/// @title USD Chainlink and Pyth price aggregator for more accurate pricing.
/// @notice Based on the Flat Money oracle module
/// @dev `latestRoundData` function returns the fresher price between Chainlink and Pyth
contract ChainlinkPythPriceAggregator is IChainlinkAggregatorV3, IGmxCustomPriceFeedProvider {
  using SafeMath for uint256;
  using SignedSafeMath for int256;
  using SignedSafeMath for int64;

  address public override asset;
  ChainlinkPythPriceLib.OracleData public oracleData;
  IPyth public pythOracleContract;

  uint8 public immutable onChainOracleDecimals;
  uint256 public immutable onChainOracleDecimalsAdjustmentFactor;

  constructor(address _asset, IPyth _pythOracleContract, ChainlinkPythPriceLib.OracleData memory _oracleData) {
    asset = _asset;
    pythOracleContract = _pythOracleContract;
    oracleData = _oracleData;
    uint8 _decimals = IChainlinkAggregatorV3(_oracleData.onchainOracle.oracleContract).decimals();
    require(_decimals == 8, "Invalid onchain oracle decimals");
    onChainOracleDecimals = _decimals;
    onChainOracleDecimalsAdjustmentFactor = 10 ** (uint256(18).sub(_decimals));
  }

  function decimals() external view override returns (uint8) {
    return onChainOracleDecimals;
  }

  /// @notice Get the min and max USD price of the asset.
  /// @dev Prices are in the same decimals as provided by the on-chain oracle (Chainlink), typically 8 decimals.
  /// @dev shouldn't assume always in 8 decimals
  /// @dev Used for GMX market integration
  function getTokenMinMaxPrice(bool useMinMax) external view override returns (IGmxPrice.Price memory priceMinMax) {
    return
      ChainlinkPythPriceLib.getTokenMinMaxPrice(
        useMinMax,
        pythOracleContract,
        oracleData,
        onChainOracleDecimalsAdjustmentFactor
      );
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
    returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
  {
    (uint256 price, uint256 timestamp, ) = ChainlinkPythPriceLib.getPrice(
      oracleData,
      pythOracleContract,
      onChainOracleDecimalsAdjustmentFactor
    );

    answer = int256(price.div(onChainOracleDecimalsAdjustmentFactor)); // e.g. convert 18 -> 8 decimals
    updatedAt = timestamp;

    return (0, answer, 0, updatedAt, 0);
  }
}
