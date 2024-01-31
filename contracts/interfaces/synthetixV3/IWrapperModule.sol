// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

/**
 * @title Module for synth wrappers
 */
interface IWrapperModule {
  struct OrderFees {
    uint256 fixedFees;
    uint256 utilizationFees;
    int256 skewFees;
    int256 wrapperFees;
  }

  /**
   * @notice Wraps the specified amount and returns similar value of synth minus the fees.
   * @dev Fees are collected from the user by way of the contract returning less synth than specified amount of collateral.
   * @param marketId Id of the market used for the trade.
   * @param wrapAmount Amount of collateral to wrap.  This amount gets deposited into the market collateral manager.
   * @param minAmountReceived The minimum amount of synths the trader is expected to receive, otherwise the transaction will revert.
   * @return amountToMint Amount of synth returned to user.
   * @return fees breakdown of all fees. in this case, only wrapper fees are returned.
   */
  function wrap(
    uint128 marketId,
    uint256 wrapAmount,
    uint256 minAmountReceived
  ) external returns (uint256 amountToMint, OrderFees memory fees);

  /**
   * @notice Unwraps the synth and returns similar value of collateral minus the fees.
   * @dev Transfers the specified synth, collects fees through configured fee collector, returns collateral minus fees to trader.
   * @param marketId Id of the market used for the trade.
   * @param unwrapAmount Amount of synth trader is unwrapping.
   * @param minAmountReceived The minimum amount of collateral the trader is expected to receive, otherwise the transaction will revert.
   * @return returnCollateralAmount Amount of collateral returned.
   * @return fees breakdown of all fees. in this case, only wrapper fees are returned.
   */
  function unwrap(
    uint128 marketId,
    uint256 unwrapAmount,
    uint256 minAmountReceived
  ) external returns (uint256 returnCollateralAmount, OrderFees memory fees);
}
