// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {IGmxPrice} from "../../interfaces/gmx/IGmxPrice.sol";
import {IGmxCustomPriceFeedProvider} from "../../interfaces/gmx/IGmxCustomPriceFeedProvider.sol";
import {IAssetHandler} from "../../interfaces/IAssetHandler.sol";
import {IGmxDataStore} from "../../interfaces/gmx/IGmxDataStore.sol";
import {IGmxReader} from "../../interfaces/gmx/IGmxReader.sol";
import {IGmxMarket} from "../../interfaces/gmx/IGmxMarket.sol";
import {GmxDataStoreLib} from "./GmxDataStoreLib.sol";
import {FullMath} from "@uniswap/v3-core/contracts/libraries/FullMath.sol";
import {SafeMath} from "@openzeppelin/contracts/math/SafeMath.sol";
import {IAggregatorV3Interface as IChainlinkAggregatorV3} from "../../interfaces/IAggregatorV3Interface.sol";
import {IGmxVirtualTokenResolver} from "../../interfaces/gmx/IGmxVirtualTokenResolver.sol";
import {GmxStructs} from "./GmxStructs.sol";
import {PythPriceLib} from "../pyth/PythPriceLib.sol";
import {ChainlinkPythPriceLib} from "../chainlinkPyth/ChainlinkPythPriceLib.sol";
import {IPyth} from "../../interfaces/pyth/IPyth.sol";
import {IAggregatorV3Interface as IChainlinkAggregatorV3} from "../../interfaces/IAggregatorV3Interface.sol";

library GmxPriceLib {
  using GmxDataStoreLib for IGmxDataStore;
  using SafeMath for uint256;

  struct GmxPriceDependecies {
    IGmxReader reader;
    IGmxDataStore dataStore;
    address assetHandler;
    IGmxVirtualTokenResolver virtualTokenResolver;
  }

  uint256 public constant FLOAT_PRECISION = 10 ** 30;
  bytes32 private constant MAX_PNL_FACTOR_FOR_WITHDRAWALS = keccak256(abi.encode("MAX_PNL_FACTOR_FOR_WITHDRAWALS"));

  function adjustPrice(
    GmxPriceDependecies memory deps,
    GmxStructs.VirtualTokenOracleSetting memory virtualTokenOracleSetting,
    uint256 price,
    address token
  ) internal view returns (uint256 multiplier) {
    // formula for decimals for price feed multiplier: 60 - (external price feed decimals) - (token decimals)
    // get preset multiplier from the virtual token resolver
    multiplier = virtualTokenOracleSetting.virtualTokenMultiplier;
    // if there is no preset multiplier, get the multiplier from the data store
    if (multiplier == 0) {
      // adjust the prices that are in 8 decimals, to be in (30 - tokenDecimals) decimals
      // https://github.com/gmx-io/gmx-synthetics/blob/main/contracts/oracle/ChainlinkPriceFeedUtils.sol

      multiplier = deps.dataStore.getPriceFeedMultiplier(token);
    }
    return FullMath.mulDiv(price, multiplier, FLOAT_PRECISION);
  }

  function getTokenMinMaxPriceFromOracle(
    GmxPriceDependecies memory deps,
    GmxStructs.VirtualTokenOracleSetting memory virtualTokenOracleSetting,
    address token
  ) internal view returns (IGmxPrice.Price memory) {
    if (virtualTokenOracleSetting.oracleLookupType == GmxStructs.OracleLookupType.ChainlinkPythLib) {
      uint8 onChainOracleDecimals = IChainlinkAggregatorV3(virtualTokenOracleSetting.onchainOracle.oracleContract)
        .decimals();
      return
        ChainlinkPythPriceLib.getTokenMinMaxPrice({
          useMinMax: false,
          pythOracleContract: IPyth(virtualTokenOracleSetting.pythOracleContract),
          oracleData: ChainlinkPythPriceLib.OracleData({
            onchainOracle: virtualTokenOracleSetting.onchainOracle,
            offchainOracle: virtualTokenOracleSetting.pythOracleData
          }),
          onChainOracleDecimalsAdjustmentFactor: 10 ** (uint256(18).sub(onChainOracleDecimals))
        });
    } else if (virtualTokenOracleSetting.oracleLookupType == GmxStructs.OracleLookupType.PythLib) {
      return
        PythPriceLib.getTokenMinMaxPrice({
          useMinMax: false,
          pythOracleContract: IPyth(virtualTokenOracleSetting.pythOracleContract),
          oracleData: virtualTokenOracleSetting.pythOracleData
        });
    }

    address aggregator = IAssetHandler(deps.assetHandler).priceAggregators(token);
    try IGmxCustomPriceFeedProvider(aggregator).getTokenMinMaxPrice({useMinMax: false}) returns (
      IGmxPrice.Price memory priceMinMax
    ) {
      try IGmxCustomPriceFeedProvider(aggregator).asset() returns (address asset) {
        require(token == asset, "invalid asset");
      } catch {
        revert("failed to get asset");
      }
      return priceMinMax;
    } catch {
      // fallback to onchain oracle
      (, int256 _price, , , ) = IChainlinkAggregatorV3(aggregator).latestRoundData();
      require(_price > 0, "Onchain oracle price is invalid");
      return IGmxPrice.Price({min: uint256(_price), max: uint256(_price)});
    }
  }

  function getTokenMinMaxPrice(
    GmxPriceDependecies memory deps,
    address token
  ) internal view returns (IGmxPrice.Price memory) {
    GmxStructs.VirtualTokenOracleSetting memory virtualTokenOracleSetting = deps
      .virtualTokenResolver
      .getVirtualTokenOracleSettings(token);
    IGmxPrice.Price memory priceMinMaxFromOracle = getTokenMinMaxPriceFromOracle(
      deps,
      virtualTokenOracleSetting,
      token
    );
    return
      IGmxPrice.Price({
        min: adjustPrice(deps, virtualTokenOracleSetting, priceMinMaxFromOracle.min, token),
        max: adjustPrice(deps, virtualTokenOracleSetting, priceMinMaxFromOracle.max, token)
      });
  }

  function getMarketLpTokenPrice(
    GmxPriceDependecies memory deps,
    IGmxMarket.Props memory market,
    bool maximize
  ) internal view returns (uint256 lpTokenPriceD18) {
    // marketPrice is in 30 decimals
    (int256 marketPrice, ) = deps.reader.getMarketTokenPrice({
      _dataStore: deps.dataStore,
      _market: market,
      _indexTokenPrice: GmxPriceLib.getTokenMinMaxPrice(deps, market.indexToken),
      _longTokenPrice: GmxPriceLib.getTokenMinMaxPrice(deps, market.longToken),
      _shortTokenPrice: GmxPriceLib.getTokenMinMaxPrice(deps, market.shortToken),
      _pnlFactorType: MAX_PNL_FACTOR_FOR_WITHDRAWALS,
      _maximize: maximize
    });
    return marketPrice <= 0 ? 0 : uint256(marketPrice).div(1e12); //  convert to 18 decimals
  }
}
