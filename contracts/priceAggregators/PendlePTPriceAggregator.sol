// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {SignedSafeMath} from "@openzeppelin/contracts/math/SignedSafeMath.sol";

import {IPoolFactory} from "../interfaces/IPoolFactory.sol";
import {IAssetHandler} from "../interfaces/IAssetHandler.sol";
import {IAggregatorV3Interface} from "../interfaces/IAggregatorV3Interface.sol";

contract PendlePTPriceAggregator is IAggregatorV3Interface {
  using SignedSafeMath for int256;

  IAggregatorV3Interface public immutable pendleChainlinkOracle;
  uint8 public immutable pendleChainlinkOracleDecimals;

  IPoolFactory public poolFactory;
  address public syEquivalentYieldToken;
  IAggregatorV3Interface public yieldTokenAggregator;
  uint8 public yieldTokenAggregatorDecimals;

  constructor(
    address _syEquivalentYieldToken,
    IAggregatorV3Interface _pendleChainlinkOracle,
    IPoolFactory _poolFactory
  ) {
    require(address(_pendleChainlinkOracle) != address(0) && address(_poolFactory) != address(0), "invalid address");

    poolFactory = _poolFactory;
    syEquivalentYieldToken = _syEquivalentYieldToken;
    pendleChainlinkOracle = _pendleChainlinkOracle;
    pendleChainlinkOracleDecimals = _pendleChainlinkOracle.decimals();

    updateUnderlyingAggregator();
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
    (, int256 ptPrice, , uint256 ptPriceUpdateAt, ) = pendleChainlinkOracle.latestRoundData();
    (, int256 yieldTokenPrice, , uint256 yieldTokenUpdatedAt, ) = yieldTokenAggregator.latestRoundData();

    // Answer is in yieldTokenAggregator decimals
    answer = (ptPrice.mul(yieldTokenPrice)).div(int256(10 ** pendleChainlinkOracleDecimals));
    // Adjust answer to 8 decimals
    answer = answer.mul(1e8).div(int256(10 ** yieldTokenAggregatorDecimals));

    return (0, answer, 0, yieldTokenUpdatedAt > ptPriceUpdateAt ? ptPriceUpdateAt : yieldTokenUpdatedAt, 0);
  }

  /// @dev In case the yield token aggregator is changed within our system, anyone can call this function to update the PT aggregator (eliminates the need for redeploying the contract)
  function updateUnderlyingAggregator() public {
    address _yieldTokenAggregator = IAssetHandler(poolFactory.getAssetHandler()).priceAggregators(
      syEquivalentYieldToken
    );

    require(_yieldTokenAggregator != address(0), "invalid aggregator");

    uint8 _yieldTokenAggregatorDecimals = IAggregatorV3Interface(_yieldTokenAggregator).decimals();

    require(_yieldTokenAggregatorDecimals > 0, "invalid decimals");

    yieldTokenAggregator = IAggregatorV3Interface(_yieldTokenAggregator);
    yieldTokenAggregatorDecimals = _yieldTokenAggregatorDecimals;
  }
}
