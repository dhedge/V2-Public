// SPDX-License-Identifier: MIT
pragma solidity >=0.8.28;

interface IFluidDexT1 {
  struct Implementations {
    address shift;
    address admin;
    address colOperations;
    address debtOperations;
    address perfectOperationsAndOracle;
  }

  struct ConstantViews {
    uint256 dexId;
    address liquidity;
    address factory;
    Implementations implementations;
    address deployerContract;
    address token0;
    address token1;
    bytes32 supplyToken0Slot;
    bytes32 borrowToken0Slot;
    bytes32 supplyToken1Slot;
    bytes32 borrowToken1Slot;
    bytes32 exchangePriceToken0Slot;
    bytes32 exchangePriceToken1Slot;
    uint256 oracleMapping;
  }

  struct Oracle {
    uint256 twap1by0; // TWAP price of token1 per token0
    uint256 lowestPrice1by0; // lowest price point
    uint256 highestPrice1by0; // highest price point
    uint256 twap0by1; // TWAP price of token0 per token1
    uint256 lowestPrice0by1; // lowest price point
    uint256 highestPrice0by1; // highest price point
  }

  struct PricesAndExchangePrice {
    uint256 lastStoredPrice; // last stored price in 1e27 decimals
    uint256 centerPrice; // last stored price in 1e27 decimals
    uint256 upperRange; // price at upper range in 1e27 decimals
    uint256 lowerRange; // price at lower range in 1e27 decimals
    uint256 geometricMean; // geometric mean of upper range & lower range in 1e27 decimals
    uint256 supplyToken0ExchangePrice;
    uint256 borrowToken0ExchangePrice;
    uint256 supplyToken1ExchangePrice;
    uint256 borrowToken1ExchangePrice;
  }

  struct CollateralReserves {
    uint256 token0RealReserves;
    uint256 token1RealReserves;
    uint256 token0ImaginaryReserves;
    uint256 token1ImaginaryReserves;
  }

  struct ConstantViews2 {
    uint256 token0NumeratorPrecision;
    uint256 token0DenominatorPrecision;
    uint256 token1NumeratorPrecision;
    uint256 token1DenominatorPrecision;
  }

  error FluidDexPricesAndExchangeRates(PricesAndExchangePrice pex_);

  /// @notice Returns the pool constants including token0 and token1 addresses
  function constantsView() external view returns (ConstantViews memory constantsView_);

  /// @notice Returns the pool constants2 including precision values
  function constantsView2() external view returns (ConstantViews2 memory constantsView2_);

  /// @notice Returns TWAP oracle prices for the given time windows
  /// @param secondsAgos_ Array of seconds ago for which TWAP is needed.
  ///        If user sends [1800] then twaps_ will return TWAP from 1800 seconds ago to now.
  ///        If user sends [10, 30, 60] then twaps_ will return [10-0, 30-10, 60-30] segments.
  /// @return twaps_ TWAP price, lowest price (aka minima) & highest price (aka maxima) between secondsAgo checkpoints
  /// @return currentPrice_ Price of pool after the most recent swap
  function oraclePrice(
    uint256[] memory secondsAgos_
  ) external view returns (Oracle[] memory twaps_, uint256 currentPrice_);

  /// @notice Toggles the oracle activation
  /// @param turnOn_ Whether to turn on or off the oracle
  function toggleOracleActivation(bool turnOn_) external;

  // reverts with FluidDexPricesAndExchangeRates(pex_);
  function getPricesAndExchangePrices() external;

  /// @notice Returns the collateral reserves of the pool
  function getCollateralReserves(
    uint256 geometricMean_,
    uint256 upperRange_,
    uint256 lowerRange_,
    uint256 token0SupplyExchangePrice_,
    uint256 token1SupplyExchangePrice_
  ) external view returns (CollateralReserves memory c_);
}
