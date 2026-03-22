//
//        __  __    __  ________  _______    ______   ________
//       /  |/  |  /  |/        |/       \  /      \ /        |
//   ____$$ |$$ |  $$ |$$$$$$$$/ $$$$$$$  |/$$$$$$  |$$$$$$$$/
//  /    $$ |$$ |__$$ |$$ |__    $$ |  $$ |$$ | _$$/ $$ |__
// /$$$$$$$ |$$    $$ |$$    |   $$ |  $$ |$$ |/    |$$    |
// $$ |  $$ |$$$$$$$$ |$$$$$/    $$ |  $$ |$$ |$$$$ |$$$$$/
// $$ \__$$ |$$ |  $$ |$$ |_____ $$ |__$$ |$$ \__$$ |$$ |_____
// $$    $$ |$$ |  $$ |$$       |$$    $$/ $$    $$/ $$       |
//  $$$$$$$/ $$/   $$/ $$$$$$$$/ $$$$$$$/   $$$$$$/  $$$$$$$$/
//
// dHEDGE DAO - https://dhedge.org
//
// Copyright (c) dHEDGE DAO
//
// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {SafeMath} from "@openzeppelin/contracts/math/SafeMath.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IERC20Extended} from "../../../../interfaces/IERC20Extended.sol";
import {IHasAssetInfo} from "../../../../interfaces/IHasAssetInfo.sol";
import {IHasSupportedAsset} from "../../../../interfaces/IHasSupportedAsset.sol";
import {IPoolLogic} from "../../../../interfaces/IPoolLogic.sol";
import {IStableModuleV2} from "../../../../interfaces/flatMoney/v2/IStableModuleV2.sol";
import {OutsidePositionWithdrawalHelper} from "../../OutsidePositionWithdrawalHelper.sol";
import {FlatMoneyV2UNITAssetGuard} from "./FlatMoneyV2UNITAssetGuard.sol";

/// @title Asset guard for FlatMoney V2 UNIT token with OutsidePositionWithdrawalHelper
/// @notice AssetType - 35
/// @dev This guard extends FlatMoneyV2UNITAssetGuard and uses OutsidePositionWithdrawalHelper to handle
///      withdrawals via the vault's collateral asset sitting in the pool.
/// @dev IMPORTANT: This guard's getBalance returns USD VALUE (18 decimals), not token balance.
///      This is required for OutsidePositionWithdrawalHelper to calculate withdrawal amounts correctly.
///      Set USDPriceAggregator for this asset type since getBalance already returns USD value.
contract FlatMoneyV2UNITOutsideWithdrawalAssetGuard is OutsidePositionWithdrawalHelper, FlatMoneyV2UNITAssetGuard {
  using SafeMath for uint256;

  address public immutable collateral;
  uint256 public immutable collateralDecimals;

  constructor(address _collateral) {
    require(_collateral != address(0), "invalid collateral");

    uint256 decimals = IERC20Extended(_collateral).decimals();
    require(decimals <= 18, "invalid decimals");

    collateral = _collateral;
    collateralDecimals = decimals;
  }

  /// @notice Returns the USD value (18 decimals) of the UNIT asset held by the pool.
  /// @dev Returns VALUE in USD, not token balance. This is required for OutsidePositionWithdrawalHelper.
  ///      Reverts if there is a pending order to prevent deposits/withdrawals during order execution.
  /// @param _pool Pool address
  /// @param _asset UNIT asset address (stableModule)
  /// @return balanceD18 USD value of the UNIT position in 18 decimals
  function getBalance(
    address _pool,
    address _asset
  ) public view override(FlatMoneyV2UNITAssetGuard, OutsidePositionWithdrawalHelper) returns (uint256 balanceD18) {
    require(_hasNoBlockingOrder(_pool, _asset), "order in progress");

    uint256 unitBalanceD18 = IERC20(_asset).balanceOf(_pool);
    if (unitBalanceD18 == 0) {
      return 0;
    }

    // Returns value in collateral decimals
    uint256 collateralPerShare = IStableModuleV2(_asset).stableCollateralPerShare({
      maxAge: 24 hours,
      priceDiffCheck: true
    });
    require(collateralPerShare > 0, "invalid cps");

    uint256 collateralPriceD18 = IHasAssetInfo(IPoolLogic(_pool).factory()).getAssetPrice(collateral);

    balanceD18 = unitBalanceD18.mul(collateralPerShare).div(10 ** collateralDecimals).mul(collateralPriceD18).div(1e18);
  }

  /// @notice Returns the decimals for this asset type
  /// @dev Returns 18 since getBalance returns USD value in 18 decimals
  /// @return decimals Always 18
  function getDecimals(address) external pure override returns (uint256 decimals) {
    decimals = 18;
  }

  function addAssetCheck(address _poolLogic, IHasSupportedAsset.Asset calldata _asset) public view override {
    require(!_asset.isDeposit, "deposit not supported");

    super.addAssetCheck(_poolLogic, _asset);
  }

  /// @notice Withdrawal processing for UNIT asset using OutsidePositionWithdrawalHelper
  /// @dev Instead of withdrawing UNIT tokens directly, withdraws the vault's collateral asset
  ///      sitting in the pool proportionally to the withdrawer's share of the UNIT position value.
  /// @param _pool Address of the pool
  /// @param _asset UNIT asset address
  /// @param _withdrawPortion Portion to withdraw, in 10^18 scale
  /// @return withdrawAsset Collateral asset address to withdraw
  /// @return withdrawBalance Amount of collateral asset to withdraw
  /// @return transactions Transactions to be executed (empty for this implementation)
  function withdrawProcessing(
    address _pool,
    address _asset,
    uint256 _withdrawPortion,
    address
  )
    external
    view
    override
    returns (address withdrawAsset, uint256 withdrawBalance, MultiTransaction[] memory transactions)
  {
    (withdrawAsset, withdrawBalance, transactions) = _withdrawProcessing(_pool, _asset, _withdrawPortion, collateral);
  }
}
