// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma abicoder v2;

import {SignedSafeMath} from "@openzeppelin/contracts/math/SignedSafeMath.sol";
import {SafeMath} from "@openzeppelin/contracts/math/SafeMath.sol";

import {IAggregatorV3Interface as IChainlinkAggregatorV3} from "../interfaces/IAggregatorV3Interface.sol";
import {IPyth} from "../interfaces/pyth/IPyth.sol";
import {IGmxPrice} from "../interfaces/gmx/IGmxPrice.sol";
import {IGmxCustomPriceFeedProvider} from "../interfaces/gmx/IGmxCustomPriceFeedProvider.sol";
import {PythPriceLib} from "../utils/pyth/PythPriceLib.sol";

contract PythPriceAggregator is IChainlinkAggregatorV3, IGmxCustomPriceFeedProvider {
  using SafeMath for uint256;
  using SignedSafeMath for int256;
  using SignedSafeMath for int64;

  address public override asset;
  PythPriceLib.OffchainOracle public oracleData;
  IPyth public pythOracleContract;

  constructor(address _asset, IPyth _pythOracleContract, PythPriceLib.OffchainOracle memory _oracleData) {
    asset = _asset;
    pythOracleContract = _pythOracleContract;
    oracleData = _oracleData;
    IPyth.Price memory priceData = pythOracleContract.getPriceUnsafe(oracleData.priceId);
    require(PythPriceLib.abs(int256(priceData.expo)) == 8, "Invalid Pyth oracle expo");
  }

  function decimals() external pure override returns (uint8) {
    return 8;
  }

  function getTokenMinMaxPrice(bool useMinMax) external view override returns (IGmxPrice.Price memory priceMinMax) {
    priceMinMax = PythPriceLib.getTokenMinMaxPrice({
      useMinMax: useMinMax,
      pythOracleContract: pythOracleContract,
      oracleData: oracleData
    });
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
    (uint256 price, uint256 timestamp, ) = PythPriceLib.getOffchainPrice(pythOracleContract, oracleData);

    updatedAt = timestamp;

    return (0, int256(price), 0, updatedAt, 0);
  }
}
