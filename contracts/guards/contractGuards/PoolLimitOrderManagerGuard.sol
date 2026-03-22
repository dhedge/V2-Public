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
// Copyright (c) 2025 dHEDGE DAO
//
// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma abicoder v2;

import {IGuard} from "../../interfaces/guards/IGuard.sol";
import {IHasSupportedAsset} from "../../interfaces/IHasSupportedAsset.sol";
import {IPoolLimitOrderManager} from "../../interfaces/IPoolLimitOrderManager.sol";
import {ITransactionTypes} from "../../interfaces/ITransactionTypes.sol";
import {TxDataUtils} from "../../utils/TxDataUtils.sol";

contract PoolLimitOrderManagerGuard is TxDataUtils, ITransactionTypes, IGuard {
  /// @param _poolManagerLogic Pool manager logic address
  /// @param _to PoolLimitOrderManager address
  /// @param _data Transaction data
  /// @return txType Transaction type
  /// @return isPublic If the transaction is public or private
  function txGuard(
    address _poolManagerLogic,
    address _to,
    bytes memory _data
  ) external view override returns (uint16 txType, bool) {
    bytes4 method = getMethod(_data);

    // To use PoolLimitOrderManager, manager must enable an "asset" which is designed to track tokens which are located
    // in the pool's withdrawal vault after limit order is executed. This "asset" is EasySwapperV2 address.
    if (method == IPoolLimitOrderManager.createLimitOrder.selector) {
      _validateSupportedAssets(_poolManagerLogic, _to, _data);

      txType = uint16(TransactionType.LimitOrderCreate);
    } else if (method == IPoolLimitOrderManager.modifyLimitOrder.selector) {
      _validateSupportedAssets(_poolManagerLogic, _to, _data);

      txType = uint16(TransactionType.LimitOrderModify);
    } else if (method == IPoolLimitOrderManager.deleteLimitOrder.selector) {
      txType = uint16(TransactionType.LimitOrderDelete);
    }

    return (txType, false);
  }

  function _validateSupportedAssets(address _poolManagerLogic, address _to, bytes memory _data) internal view {
    // PoolLimitOrderManager stores EasySwapperV2 address which is used an as "asset" with asset type 30 for accounting tokens in WithdrawalVault belonging to the dHEDGE vault.
    address easySwapper = IPoolLimitOrderManager(_to).easySwapper();
    // This is set to USDC and this is what normally keepers settle limit orders to.
    address settlementToken = IPoolLimitOrderManager(_to).limitOrderSettlementToken();

    // Before opening a limit order, need to ensure that once order is executed, "asset" with type 30 (EasySwapperV2) is enabled
    // so it can account for tokens which WithdrawalVault belonging to dHEDGE vault will receive after limit order execution.
    // Also normally keepers settle tokens received from limit order execution to USDC, so it is useful to check if USDC is enabled (if it becomes disabled later,
    // keepers won't be able to execute settlement order, see EasySwapperV2::completeLimitOrderWithdrawalFor)
    require(
      IHasSupportedAsset(_poolManagerLogic).isSupportedAsset(easySwapper) &&
        IHasSupportedAsset(_poolManagerLogic).isSupportedAsset(settlementToken),
      "unsupported destination asset"
    );

    IPoolLimitOrderManager.LimitOrderInfo memory orderInfo = abi.decode(
      getParams(_data),
      (IPoolLimitOrderManager.LimitOrderInfo)
    );

    // There is no direct threat without this check, but better to be explicit and allow to create limit orders only for Toros tokens
    // which are allowed to be used in the dHEDGE vaults hence enabled.
    require(IHasSupportedAsset(_poolManagerLogic).isSupportedAsset(orderInfo.pool), "unsupported source asset");
  }
}
