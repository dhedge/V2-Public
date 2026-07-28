// SPDX-License-Identifier: MIT
pragma solidity >=0.7.6;

import {IAssetGuard} from "../../interfaces/guards/IAssetGuard.sol";
import {IERC20Extended} from "../../interfaces/IERC20Extended.sol";
import {IHasSupportedAsset} from "../../interfaces/IHasSupportedAsset.sol";
import {IPoolLogic} from "../../interfaces/IPoolLogic.sol";
import {IPoolManagerLogic} from "../../interfaces/IPoolManagerLogic.sol";

/// @title OutsidePositionWithdrawalHelper
/// @notice Helper for withdrawing from complex positions using a pre-configured withdrawal asset sitting in the pool
/// @dev IMPORTANT: Contracts inheriting from this helper MUST implement `getBalance` to return a VALUE in USD
///      with 18 decimals, NOT a token balance. The `_withdrawProcessing` function uses this value to calculate
///      the proportional amount of withdrawal asset to transfer.
///      The only exception is when `_valueToWithdrawAssetAmount` is overridden: in that case `getBalance` may be
///      denominated differently (e.g. directly in the withdrawal asset), as long as the override converts the
///      value into a withdrawal asset token amount.
abstract contract OutsidePositionWithdrawalHelper {
  function getBalance(address, address) public view virtual returns (uint256);

  /// @notice Helper function for withdrawing using specially configured asset sitting in the pool outside
  /// @param _pool PoolLogic address
  /// @param _asset Complex position address
  /// @param _withdrawPortion Portion to withdraw
  /// @param _withdrawAsset Asset address to withdraw to (sitting in the pool outside the position)
  /// @return withdrawAsset Asset address to withdraw
  /// @return withdrawBalance Amount to withdraw
  /// @return transactions Transactions to be executed
  function _withdrawProcessing(
    address _pool,
    address _asset,
    uint256 _withdrawPortion,
    address _withdrawAsset
  )
    internal
    view
    returns (address withdrawAsset, uint256 withdrawBalance, IAssetGuard.MultiTransaction[] memory transactions)
  {
    uint256 valueToWithdraw = _mulDiv(getBalance(_pool, _asset), _withdrawPortion, 1e18);

    if (valueToWithdraw == 0) {
      return (withdrawAsset, withdrawBalance, transactions);
    }

    withdrawAsset = _withdrawAsset;
    withdrawBalance = _calculateWithdrawBalance(
      _pool,
      IPoolLogic(_pool).poolManagerLogic(),
      withdrawAsset,
      valueToWithdraw,
      _withdrawPortion
    );

    return (withdrawAsset, withdrawBalance, transactions);
  }

  /// @notice Calculates how many withdrawal asset tokens should be paid out for the value being withdrawn
  /// @param _pool PoolLogic address
  /// @param _poolManagerLogic PoolManagerLogic address of `_pool`
  /// @param _withdrawAsset Asset address to withdraw (sitting in the pool outside the position)
  /// @param _valueToWithdraw Value to withdraw, in the denomination expected by `_valueToWithdrawAssetAmount`
  /// @param _withdrawPortion Portion to withdraw
  /// @return withdrawBalance Amount of withdrawal asset to withdraw
  function _calculateWithdrawBalance(
    address _pool,
    address _poolManagerLogic,
    address _withdrawAsset,
    uint256 _valueToWithdraw,
    uint256 _withdrawPortion
  ) internal view returns (uint256 withdrawBalance) {
    // If withdrawal asset configured for current pool is not enabled, then withdraw should revert
    require(IHasSupportedAsset(_poolManagerLogic).isSupportedAsset(_withdrawAsset), "withdrawal asset not enabled");

    uint256 withdrawAssetBalanceInPool = IERC20Extended(_withdrawAsset).balanceOf(_pool);

    // how many withdrawal asset tokens should be withdrawn for depositor's portion of the position
    withdrawBalance = _valueToWithdrawAssetAmount(
      _poolManagerLogic,
      _withdrawAsset,
      withdrawAssetBalanceInPool,
      _valueToWithdraw
    );

    // Revert withdraw from single remaining depositor, assuming that integration will only be available for Toros
    require(_withdrawPortion < 1e18, "invalid withdraw portion");

    // the above plus compensation for decreased withdrawal asset balance
    withdrawBalance = _mulDiv(withdrawBalance, 1e18, uint256(1e18) - _withdrawPortion);

    // Otherwise there is not enough withdrawal asset balance to cover the position portion
    require(withdrawAssetBalanceInPool >= withdrawBalance, "not enough available balance_1");
  }

  /// @notice Converts the value being withdrawn into a withdrawal asset token amount
  /// @dev Default implementation treats `_valueToWithdraw` as USD value (18 decimals) and converts it
  ///      using the pool's withdrawal asset balance to value ratio.
  ///      Override when `getBalance` is already denominated in the withdrawal asset (identity conversion).
  function _valueToWithdrawAssetAmount(
    address _poolManagerLogic,
    address _withdrawAsset,
    uint256 _withdrawAssetBalanceInPool,
    uint256 _valueToWithdraw
  ) internal view virtual returns (uint256 withdrawAssetAmount) {
    uint256 withdrawAssetValueInPool = IPoolManagerLogic(_poolManagerLogic).assetValue(
      _withdrawAsset,
      _withdrawAssetBalanceInPool
    );

    // if withdrawal asset is enabled, but has no balance or no value (for some reason), then withdraw should revert
    require(withdrawAssetValueInPool > 0, "not enough available balance_0");

    withdrawAssetAmount = _mulDiv(_withdrawAssetBalanceInPool, _valueToWithdraw, withdrawAssetValueInPool);
  }

  /// @dev Overflow-checked `(_x * _y) / _denominator`, compatible with both 0.7.6 and 0.8.x compilers
  function _mulDiv(uint256 _x, uint256 _y, uint256 _denominator) private pure returns (uint256 result) {
    uint256 product = _x * _y;
    require(_x == 0 || product / _x == _y, "multiplication overflow");
    result = product / _denominator;
  }
}
