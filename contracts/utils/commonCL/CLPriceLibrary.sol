// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

import {SafeMathUpgradeable} from "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";
import {IERC20Extended} from "../../interfaces/IERC20Extended.sol";
import {IHasAssetInfo} from "../../interfaces/IHasAssetInfo.sol";
import {DhedgeMath} from "../DhedgeMath.sol";

library CLPriceLibrary {
  using SafeMathUpgradeable for uint24;
  using SafeMathUpgradeable for uint160;
  using SafeMathUpgradeable for uint256;

  uint24 public constant MIN_THRESHOLD = 5000;

  function isSqrtPriceDeviationInRange(
    uint24 fee,
    uint160 sqrtPriceX96,
    uint160 fairSqrtPriceX96
  ) internal pure returns (bool) {
    // Check that fair price is close to current pool price
    // Threshold for the check is:
    // - minimum of 0.5%, and
    // - 50% higher than pool fee, because the pool may not get arbed if the fee is high
    uint256 threshold = fee >= MIN_THRESHOLD ? fee.mul(150).div(100) : MIN_THRESHOLD;

    return (sqrtPriceX96 < fairSqrtPriceX96.add(fairSqrtPriceX96.mul(threshold).div(1_000_000)) &&
      fairSqrtPriceX96 < sqrtPriceX96.add(fairSqrtPriceX96.mul(threshold).div(1_000_000)));
  }

  /// @notice Returns the Uni-V3 style pool square root price based on underlying oracle prices
  /// @dev note token0 and token1 must be in the same order as the uni pool we're comparing too
  /// @param factory dHEDGE Factory address
  /// @param token0 Uni-V3 style pool token0
  /// @param token1 Uni-V3 style pool token1
  /// @return sqrtPriceX96 square root price as a Q64.96
  function getFairSqrtPriceX96(
    address factory,
    address token0,
    address token1
  ) internal view returns (uint160 sqrtPriceX96) {
    uint256 token0Price = IHasAssetInfo(factory).getAssetPrice(token0);
    uint256 token1Price = IHasAssetInfo(factory).getAssetPrice(token1);
    uint8 token0Decimals = IERC20Extended(token0).decimals();
    uint8 token1Decimals = IERC20Extended(token1).decimals();
    sqrtPriceX96 = calculateSqrtPrice(token0Price, token1Price, token0Decimals, token1Decimals);
  }

  /// @notice Returns the Uni-V3 style pool square root price based on prices and token decimals
  /// @dev note token0 and token1 must be in the same order as the uni pool we're comparing too
  /// @param token0Price Chainlink Price of token0
  /// @param token1Price Chainlink Price of token1
  /// @param token0Decimals The erc20 tokens decimals
  /// @param token1Decimals The erc20 tokens decimals
  /// @return sqrtPriceX96 square root price as a Q64.96
  function calculateSqrtPrice(
    uint256 token0Price,
    uint256 token1Price,
    uint8 token0Decimals,
    uint8 token1Decimals
  ) internal pure returns (uint160 sqrtPriceX96) {
    uint256 priceRatio;
    uint8 token1DecimalsConversion;

    // Prices are in 18 decimals
    // price = token1Amount / token0Amount =  (token0Price * token1Decimals) / (token0Price * token0Decimals)
    // sqrtPriceX96 = sqrt(price) / (2^96)

    // adjust for the part: (token0Price * token1Decimals) / token0Price
    // ideal for token1Decimals being 18
    if (token1Decimals < 18) {
      token1DecimalsConversion = ((18 - token1Decimals) / 2 + 1);
      priceRatio = token0Price.mul(10 ** (token1Decimals + token1DecimalsConversion * 2)).div(token1Price);
    } else {
      priceRatio = token0Price.mul(10 ** token1Decimals).div(token1Price);
    }

    // Overflow protection for the price ratio shift left
    bool overflowProtection;
    if (priceRatio > 10 ** 18) {
      overflowProtection = true;
      priceRatio = priceRatio.div(10 ** 10); // decrease 10 decimals
    }
    require(priceRatio <= 10 ** 18 && priceRatio > 1000, "Uni v3 price ratio out of bounds");

    sqrtPriceX96 = uint160(DhedgeMath.sqrt((priceRatio << 192).div(10 ** token0Decimals)));

    if (overflowProtection) {
      sqrtPriceX96 = uint160(sqrtPriceX96.mul(10 ** 5)); // increase 5 decimals (revert adjustment)
    }

    // reverse the init token1Decimals adjustment
    sqrtPriceX96 = uint160(sqrtPriceX96.div((10 ** (token1DecimalsConversion))));
  }
}
