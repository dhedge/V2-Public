// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

import {SafeMath} from "@openzeppelin/contracts/math/SafeMath.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IAssetGuard} from "../../interfaces/guards/IAssetGuard.sol";
import {IHasSupportedAsset} from "../../interfaces/IHasSupportedAsset.sol";
import {IPoolLogic} from "../../interfaces/IPoolLogic.sol";
import {IPoolManagerLogic} from "../../interfaces/IPoolManagerLogic.sol";

abstract contract OutsidePositionWithdrawalHelper {
  using SafeMath for uint256;

  function getBalance(address, address) public view virtual returns (uint256) {
    revert("not implemented");
  }

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
    uint256 valueToWithdraw = getBalance(_pool, _asset).mul(_withdrawPortion).div(1e18);

    if (valueToWithdraw == 0) {
      return (withdrawAsset, withdrawBalance, transactions);
    }

    withdrawAsset = _withdrawAsset;
    address poolManagerLogic = IPoolLogic(_pool).poolManagerLogic();

    // If withdrawal asset configured for current pool is not enabled, then withdraw should revert
    require(IHasSupportedAsset(poolManagerLogic).isSupportedAsset(withdrawAsset), "withdrawal asset not enabled");

    uint256 withdrawAssetBalanceInPool = IERC20(withdrawAsset).balanceOf(_pool);
    uint256 withdrawAssetValueInPool = IPoolManagerLogic(poolManagerLogic).assetValue(
      withdrawAsset,
      withdrawAssetBalanceInPool
    );

    // if withdrawal asset is enabled, but has no balance or no value (for some reason), then withdraw should revert
    require(withdrawAssetValueInPool > 0, "not enough available balance_0");

    // Revert withdraw from single remaining depositor, assuming that integration will only be available for Toros
    require(_withdrawPortion < 1e18, "invalid withdraw portion");

    // how many withdrawal asset tokens should be withdrawn for depositor's portion of leverage position
    withdrawBalance = withdrawAssetBalanceInPool.mul(valueToWithdraw).div(withdrawAssetValueInPool);
    uint256 additionalWithdrawalFactor = uint256(1e36).div(uint256(1e18).sub(_withdrawPortion));

    // the above plus compensation for decreased withdrawal asset balance
    withdrawBalance = withdrawBalance.mul(additionalWithdrawalFactor).div(1e18);

    // Otherwise there is not enough withdrawal asset balance to cover leverage position portion
    require(withdrawAssetBalanceInPool >= withdrawBalance, "not enough available balance_1");

    return (withdrawAsset, withdrawBalance, transactions);
  }
}
