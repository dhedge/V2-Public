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
// Copyright (c) 2024 dHEDGE DAO
//
// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {SafeMath} from "@openzeppelin/contracts/math/SafeMath.sol";

import {IPoolLogic} from "../../interfaces/IPoolLogic.sol";
import {IPoolManagerLogic} from "../../interfaces/IPoolManagerLogic.sol";
import {IEasySwapperV2} from "../../swappers/easySwapperV2/interfaces/IEasySwapperV2.sol";
import {IWithdrawalVault} from "../../swappers/easySwapperV2/interfaces/IWithdrawalVault.sol";
import {ClosedAssetGuard} from "./ClosedAssetGuard.sol";
import {IPoolLimitOrderManager} from "../../interfaces/IPoolLimitOrderManager.sol";

contract EasySwapperV2UnrolledAssetsGuard is ClosedAssetGuard {
  using SafeMath for uint256;

  IPoolLimitOrderManager public immutable poolLimitOrderManagerProxy;

  /// @param _poolLimitOrderManagerProxy It's an upgradeable contract so address is not expected to change
  constructor(address _poolLimitOrderManagerProxy) {
    require(_poolLimitOrderManagerProxy != address(0), "invalid address");

    poolLimitOrderManagerProxy = IPoolLimitOrderManager(_poolLimitOrderManagerProxy);
  }

  /// @dev Asset type 30 is used for accounting tokens in both types of WithdrawalVaults, for managers' ease of use (no need to add two separate assets)
  /// @param _pool dHEDGE vault address
  /// @param _asset In case of this asset guard, always EasySwapperV2 address
  /// @return balance Total balance accounted for both WithdrawalVaults belonging to the dHEDGE vault already in USD value
  function getBalance(address _pool, address _asset) public view override returns (uint256 balance) {
    address poolManagerLogic = IPoolLogic(_pool).poolManagerLogic();

    balance = _balanceOfWithdrawalVault(_pool, _asset, poolManagerLogic).add(
      _balanceOfLimitOrderVault(_pool, _asset, poolManagerLogic)
    );
  }

  /// @param _pool dHEDGE vault address
  /// @param _asset In case of this asset guard, always EasySwapperV2 address
  function removeAssetCheck(address _pool, address _asset) public view override {
    // It won't let to remove EasySwapperV2 "asset" if there is positive balance at least in one of the WithdrawalVaults
    super.removeAssetCheck(_pool, _asset);

    // Do not allow to remove EasySwapperV2 "asset" if there is an open limit order, because once limit order is executed,
    // tokens will be sent to WithdrawalVault and they won't be accounted hence vault losses value.
    require(poolLimitOrderManagerProxy.hasOpenLimitOrder(_pool) == false, "limit order opened");
  }

  function getDecimals(address) external pure override returns (uint256 decimals) {
    decimals = 18;
  }

  function withdrawProcessing(
    address _pool,
    address _asset,
    uint256 _withdrawPortion,
    address _to
  )
    external
    view
    override
    returns (address withdrawAsset, uint256 withdrawBalance, MultiTransaction[] memory transactions)
  {
    address poolManagerLogic = IPoolLogic(_pool).poolManagerLogic();

    uint256 withdrawalVaultBalance = _balanceOfWithdrawalVault(_pool, _asset, poolManagerLogic);
    uint256 limitOrderVaultBalance = _balanceOfLimitOrderVault(_pool, _asset, poolManagerLogic);

    // If both types are empty, early return
    if (withdrawalVaultBalance == 0 && limitOrderVaultBalance == 0) {
      return (withdrawAsset, withdrawBalance, transactions);
    }

    // If there are balances in both vaults, need to withdraw proportionally from both
    if (withdrawalVaultBalance > 0 && limitOrderVaultBalance > 0) {
      transactions = new MultiTransaction[](2);

      transactions[0] = MultiTransaction({
        to: _asset,
        txData: abi.encodeWithSelector(
          IEasySwapperV2.partialWithdraw.selector,
          _withdrawPortion,
          _to,
          IEasySwapperV2.WithdrawalVaultType.SINGLE_ASSET_WITHDRAWAL
        )
      });
      transactions[1] = MultiTransaction({
        to: _asset,
        txData: abi.encodeWithSelector(
          IEasySwapperV2.partialWithdraw.selector,
          _withdrawPortion,
          _to,
          IEasySwapperV2.WithdrawalVaultType.LIMIT_ORDER
        )
      });

      return (withdrawAsset, withdrawBalance, transactions);
    }

    // In remaining case, only one of the vaults has balance, so withdraw proportionally from that vault
    IEasySwapperV2.WithdrawalVaultType vaultType = withdrawalVaultBalance > 0
      ? IEasySwapperV2.WithdrawalVaultType.SINGLE_ASSET_WITHDRAWAL
      : IEasySwapperV2.WithdrawalVaultType.LIMIT_ORDER;

    transactions = new MultiTransaction[](1);
    transactions[0] = MultiTransaction({
      to: _asset,
      txData: abi.encodeWithSelector(IEasySwapperV2.partialWithdraw.selector, _withdrawPortion, _to, vaultType)
    });

    return (withdrawAsset, withdrawBalance, transactions);
  }

  function _balanceOfWithdrawalVault(
    address _pool,
    address _asset,
    address _poolManagerLogic
  ) internal view returns (uint256 balance) {
    IWithdrawalVault.TrackedAsset[] memory trackedAssets = IEasySwapperV2(_asset).getTrackedAssets(_pool);

    for (uint256 i; i < trackedAssets.length; ++i) {
      balance = balance.add(
        IPoolManagerLogic(_poolManagerLogic).assetValue(trackedAssets[i].token, trackedAssets[i].balance)
      );
    }
  }

  function _balanceOfLimitOrderVault(
    address _pool,
    address _asset,
    address _poolManagerLogic
  ) internal view returns (uint256 balance) {
    IWithdrawalVault.TrackedAsset[] memory trackedAssets = IEasySwapperV2(_asset).getTrackedAssetsFromLimitOrders(
      _pool
    );

    for (uint256 i; i < trackedAssets.length; ++i) {
      balance = balance.add(
        IPoolManagerLogic(_poolManagerLogic).assetValue(trackedAssets[i].token, trackedAssets[i].balance)
      );
    }
  }
}
