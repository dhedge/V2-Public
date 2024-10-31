// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;

/**
 * @title Module for market-specific configuration.
 */
interface ISpotMarketConfigurationModule {
  /**
   * @notice gets the atomic fixed fee for a given market
   * @param synthMarketId Id of the market the fee applies to.
   * @return atomicFixedFee fixed fee amount represented in bips with 18 decimals.
   * @return asyncFixedFee fixed fee amount represented in bips with 18 decimals.
   * @return wrapFee wrapping fee in %, 18 decimals. Can be negative.
   * @return unwrapFee unwrapping fee in %, 18 decimals. Can be negative.
   */
  function getMarketFees(
    uint128 synthMarketId
  ) external returns (uint256 atomicFixedFee, uint256 asyncFixedFee, int256 wrapFee, int256 unwrapFee);
}
