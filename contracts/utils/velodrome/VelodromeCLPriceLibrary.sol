// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.7.6;

import {IVelodromeCLFactory} from "../../interfaces/velodrome/IVelodromeCLFactory.sol";
import {IVelodromeCLPool} from "../../interfaces/velodrome/IVelodromeCLPool.sol";
import {SafeMathUpgradeable} from "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";
import {IHasAssetInfo} from "../../interfaces/IHasAssetInfo.sol";
import {IERC20Extended} from "../../interfaces/IERC20Extended.sol";
import {IERC20Extended} from "../../interfaces/IERC20Extended.sol";
import {DhedgeMath} from "../DhedgeMath.sol";

// library with helper methods for oracles that are concerned with computing average prices
library VelodromeCLPriceLibrary {
  using SafeMathUpgradeable for uint24;
  using SafeMathUpgradeable for int24;
  using SafeMathUpgradeable for uint160;
  using SafeMathUpgradeable for uint256;

  uint24 public constant MIN_THRESHOLD = 3000;

  /// @notice Assets the Velodrome CL pool price for the assets given is within the threshold of oracle price
  /// @param dhedgeFactory dHEDGE Factory address
  /// @param velodromeCLFactory Velodrome CL Factory
  /// @param token0 Uni pool token0
  /// @param token1 Uni pool token1
  /// @param tickSpacing tick spacing of the target pool
  /// @return sqrtPriceX96 square root price as a Q64.96
  function assertFairPrice(
    address dhedgeFactory,
    address velodromeCLFactory,
    address token0,
    address token1,
    int24 tickSpacing
  ) internal view returns (uint160 sqrtPriceX96) {
    uint24 fee = IVelodromeCLFactory(velodromeCLFactory).tickSpacingToFee(tickSpacing);
    return
      assertFairPrice(dhedgeFactory, IVelodromeCLFactory(velodromeCLFactory).getPool(token0, token1, tickSpacing), fee);
  }

  function assertFairPrice(
    address dhedgeFactory,
    address velodromeCLPool,
    uint24 fee
  ) internal view returns (uint160 sqrtPriceX96) {
    IVelodromeCLPool uniPool = IVelodromeCLPool(velodromeCLPool);
    (sqrtPriceX96, , , , , ) = uniPool.slot0();

    // Get a fair sqrtPriceX96 from asset price oracles
    // We pass the tokens in the same order as the pool is configured
    uint160 fairSqrtPriceX96 = getFairSqrtPriceX96(dhedgeFactory, uniPool.token0(), uniPool.token1());

    // Check that fair price is close to current pool price
    // Threshold for the check is:
    // - minimum of 0.3%, and
    // - 50% higher than pool fee, because the pool may not get arbed if the fee is high
    uint256 threshold = fee >= MIN_THRESHOLD ? fee.mul(150).div(100) : MIN_THRESHOLD;
    require(
      sqrtPriceX96 < fairSqrtPriceX96.add(fairSqrtPriceX96.mul(threshold).div(1_000_000)) &&
        fairSqrtPriceX96 < sqrtPriceX96.add(fairSqrtPriceX96.mul(threshold).div(1_000_000)),
      "Velodrome CL price mismatch"
    );
  }

  /// @notice Returns the Uni pool square root price based on underlying oracle prices
  /// @dev note token0 and token1 must be in the same order as the uni pool we're comparing too
  /// @param factory dHEDGE Factory address
  /// @param token0 Uni pool token0
  /// @param token1 Uni pool token1
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

  /// @notice Returns the Uni pool square root price based on prices and token decimals
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
    uint256 priceRatio = token0Price.mul(10 ** token1Decimals).div(token1Price);

    // Overflow protection for the price ratio shift left
    bool overflowProtection;
    if (priceRatio > 10 ** 18) {
      overflowProtection = true;
      priceRatio = priceRatio.div(10 ** 10); // decrease 10 decimals
    }
    require(priceRatio <= 10 ** 18 && priceRatio > 1000, "VeloCL price ratio out of bounds");

    sqrtPriceX96 = uint160(DhedgeMath.sqrt((priceRatio << 192).div(10 ** token0Decimals)));

    if (overflowProtection) {
      sqrtPriceX96 = uint160(sqrtPriceX96.mul(10 ** 5)); // increase 5 decimals (revert adjustment)
    }
  }
}
