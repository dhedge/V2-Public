// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.7.6;

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";
import "../../interfaces/IHasAssetInfo.sol";
import "../../interfaces/IERC20Extended.sol";
import "../DhedgeMath.sol";

// library with helper methods for oracles that are concerned with computing average prices
library UniswapV3PriceLibrary {
  using SafeMathUpgradeable for uint160;
  using SafeMathUpgradeable for uint256;

  // Oracle sqrt price threshold in basis points
  uint16 public constant BP_THRESHOLD = 35;

  /// @notice Assets the v3 pool price for the assets given is within the threshold of oracle price
  /// @param dhedgeFactory dHEDGE Factory address
  /// @param uniswapV3Factory UniswapV3 Factory
  /// @param token0 Uni pool token0
  /// @param token1 Uni pool token1
  /// @param fee fee of the target pool
  /// @return sqrtPriceX96 square root price as a Q64.96
  function assertFairPrice(
    address dhedgeFactory,
    address uniswapV3Factory,
    address token0,
    address token1,
    uint24 fee
  ) internal view returns (uint160 sqrtPriceX96) {
    return assertFairPrice(dhedgeFactory, IUniswapV3Factory(uniswapV3Factory).getPool(token0, token1, fee));
  }

  function assertFairPrice(address dhedgeFactory, address uniswapV3Pool) internal view returns (uint160 sqrtPriceX96) {
    IUniswapV3Pool uniPool = IUniswapV3Pool(uniswapV3Pool);
    (sqrtPriceX96, , , , , , ) = uniPool.slot0();

    // Get a fair sqrtPriceX96 from asset price oracles
    // We pass the tokens in the same order as the pool is configured
    uint160 fairSqrtPriceX96 = getFairSqrtPriceX96(dhedgeFactory, uniPool.token0(), uniPool.token1());

    // Check that fair price is close to current pool price (0.25% threshold)
    require(
      sqrtPriceX96 < fairSqrtPriceX96.add(fairSqrtPriceX96.mul(BP_THRESHOLD).div(10000)) &&
        fairSqrtPriceX96 < sqrtPriceX96.add(fairSqrtPriceX96.mul(BP_THRESHOLD).div(10000)),
      "Uni v3 LP price mismatch"
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
    uint256 priceRatio = token0Price.mul(10**token1Decimals).div(token1Price);

    // Overflow protection for the price ratio shift left
    bool overflowProtection;
    if (priceRatio > 10**18) {
      overflowProtection = true;
      priceRatio = priceRatio.div(10**10); // decrease 10 decimals
    }
    require(priceRatio <= 10**18 && priceRatio > 1000, "Uni v3 price ratio out of bounds");

    sqrtPriceX96 = uint160(DhedgeMath.sqrt((priceRatio << 192).div(10**token0Decimals)));

    if (overflowProtection) {
      sqrtPriceX96 = uint160(sqrtPriceX96.mul(10**5)); // increase 5 decimals (revert adjustment)
    }
  }
}
