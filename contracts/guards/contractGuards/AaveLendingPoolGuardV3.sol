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
pragma experimental ABIEncoderV2;

import {IAaveV3Pool} from "../../interfaces/aave/v3/IAaveV3Pool.sol";
import {ITxTrackingGuard} from "../../interfaces/guards/ITxTrackingGuard.sol";
import {IERC20} from "../../interfaces/IERC20.sol";
import {IHasSupportedAsset} from "../../interfaces/IHasSupportedAsset.sol";
import {IPoolManagerLogic} from "../../interfaces/IPoolManagerLogic.sol";
import {ITransactionTypes} from "../../interfaces/ITransactionTypes.sol";
import {TxDataUtils} from "../../utils/TxDataUtils.sol";

/// @title Transaction guard for Aave V3 lending pool contract
contract AaveLendingPoolGuardV3 is TxDataUtils, ITransactionTypes, ITxTrackingGuard {
  /// @dev Aave UI doesn't let withdrawal go through which leads to HF below 1.01
  uint256 public constant HEALTH_FACTOR_LOWER_BOUNDARY = 1.01e18;

  bool public override isTxTrackingGuard = true;

  /// @param poolManagerLogic the pool manager logic
  /// @param data the transaction data
  /// @return txType the transaction type of a given transaction data.
  /// @return isPublic if the transaction is public or private
  function txGuard(
    address poolManagerLogic,
    address to,
    bytes calldata data
  ) public view virtual override returns (uint16 txType, bool isPublic) {
    bytes4 method = getMethod(data);
    address poolLogic = IPoolManagerLogic(poolManagerLogic).poolLogic();

    // `deposit` is deprecated in favor of `supply`
    if (method == IAaveV3Pool.deposit.selector || method == IAaveV3Pool.supply.selector) {
      (address depositAsset, , address onBehalfOf, ) = abi.decode(getParams(data), (address, uint256, address, uint16));

      txType = _supply(poolLogic, poolManagerLogic, to, depositAsset, onBehalfOf);
    } else if (method == IAaveV3Pool.withdraw.selector) {
      (address withdrawAsset, , address onBehalfOf) = abi.decode(getParams(data), (address, uint256, address));

      txType = _withdraw(poolLogic, poolManagerLogic, to, withdrawAsset, onBehalfOf);
    } else if (method == IAaveV3Pool.setUserUseReserveAsCollateral.selector) {
      (address asset, ) = abi.decode(getParams(data), (address, bool));

      txType = _setUserUseReserveAsCollateral(poolManagerLogic, to, asset);
    } else if (method == IAaveV3Pool.borrow.selector) {
      (address borrowAsset, , , , address onBehalfOf) = abi.decode(
        getParams(data),
        (address, uint256, uint256, uint16, address)
      );

      txType = _borrow(poolLogic, poolManagerLogic, to, borrowAsset, onBehalfOf);
    } else if (method == IAaveV3Pool.repay.selector) {
      (address repayAsset, , , address onBehalfOf) = abi.decode(getParams(data), (address, uint256, uint256, address));

      txType = _repay(poolLogic, poolManagerLogic, to, repayAsset, onBehalfOf);
    } else if (method == IAaveV3Pool.repayWithATokens.selector) {
      (address repayAsset, , ) = abi.decode(getParams(data), (address, uint256, uint256));

      txType = _repay(poolLogic, poolManagerLogic, to, repayAsset, poolLogic);
    } else if (method == IAaveV3Pool.setUserEMode.selector) {
      txType = uint16(TransactionType.AaveSetEfficiencyMode);
    }

    return (txType, false);
  }

  function afterTxGuard(address poolManagerLogic, address to, bytes memory data) external view virtual override {
    if (_canAffectHealthFactor(data)) _afterTxGuard(poolManagerLogic, to);
  }

  /// @dev These are the actions which potentially can affect HF
  function _canAffectHealthFactor(bytes memory data) internal pure returns (bool canAffect) {
    bytes4 method = getMethod(data);

    if (method == IAaveV3Pool.borrow.selector || method == IAaveV3Pool.withdraw.selector) return true;

    if (method == IAaveV3Pool.setUserUseReserveAsCollateral.selector) {
      (, bool useAsCollateral) = abi.decode(getParams(data), (address, bool));
      return !useAsCollateral;
    }

    return false;
  }

  function _afterTxGuard(address poolManagerLogic, address to) internal view {
    address poolLogic = IPoolManagerLogic(poolManagerLogic).poolLogic();

    (, , , , , uint256 healthFactor) = IAaveV3Pool(to).getUserAccountData(poolLogic);

    require(healthFactor > HEALTH_FACTOR_LOWER_BOUNDARY, "health factor too low");
  }

  function _checkAssetsSupported(address _poolManagerLogic, address _lendingPool, address _assetToCheck) internal view {
    require(
      IHasSupportedAsset(_poolManagerLogic).isSupportedAsset(_lendingPool) &&
        IHasSupportedAsset(_poolManagerLogic).isSupportedAsset(_assetToCheck),
      "unsupported assets"
    );
  }

  function _supply(
    address poolLogic,
    address poolManagerLogic,
    address to,
    address depositAsset,
    address onBehalfOf
  ) internal view returns (uint16 txType) {
    _checkAssetsSupported(poolManagerLogic, to, depositAsset);

    require(onBehalfOf == poolLogic, "recipient is not pool");

    txType = uint16(TransactionType.AaveDeposit);
  }

  function _withdraw(
    address poolLogic,
    address poolManagerLogic,
    address to,
    address withdrawAsset,
    address onBehalfOf
  ) internal view returns (uint16 txType) {
    _checkAssetsSupported(poolManagerLogic, to, withdrawAsset);

    require(onBehalfOf == poolLogic, "recipient is not pool");

    txType = uint16(TransactionType.AaveWithdraw);
  }

  function _setUserUseReserveAsCollateral(
    address poolManagerLogic,
    address to,
    address asset
  ) internal view returns (uint16 txType) {
    _checkAssetsSupported(poolManagerLogic, to, asset);

    txType = uint16(TransactionType.AaveSetUserUseReserveAsCollateral);
  }

  /// @dev Only variable intereset rate is allowed: https://github.com/aave-dao/aave-v3-origin/blob/main/src/contracts/protocol/libraries/logic/ValidationLogic.sol#L168
  function _borrow(
    address poolLogic,
    address poolManagerLogic,
    address to,
    address borrowAsset,
    address onBehalfOf
  ) internal view returns (uint16 txType) {
    _checkAssetsSupported(poolManagerLogic, to, borrowAsset);

    require(onBehalfOf == poolLogic, "recipient is not pool");

    // limits to only one borrow asset: forbidden to remove this check as withdrawProcessing is dependent on it
    IHasSupportedAsset.Asset[] memory supportedAssets = IHasSupportedAsset(poolManagerLogic).getSupportedAssets();

    for (uint256 i; i < supportedAssets.length; ++i) {
      if (supportedAssets[i].asset == borrowAsset) {
        continue;
      }

      // returns address(0) if it's not supported in aave
      address variableDebtToken = IAaveV3Pool(to).getReserveVariableDebtToken(supportedAssets[i].asset);

      // checks if asset is not supported or debt amount is zero
      require(
        (variableDebtToken == address(0) || IERC20(variableDebtToken).balanceOf(poolLogic) == 0),
        "borrowing asset exists"
      );
    }

    txType = uint16(TransactionType.AaveBorrow);
  }

  function _repay(
    address poolLogic,
    address poolManagerLogic,
    address to,
    address repayAsset,
    address onBehalfOf
  ) internal view returns (uint16 txType) {
    _checkAssetsSupported(poolManagerLogic, to, repayAsset);

    require(onBehalfOf == poolLogic, "recipient is not pool");

    txType = uint16(TransactionType.AaveRepay);
  }
}
