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
import {IL2Pool} from "../../interfaces/aave/v3/IL2Pool.sol";
import {IPoolManagerLogic} from "../../interfaces/IPoolManagerLogic.sol";
import {AaveLendingPoolGuardV3} from "./AaveLendingPoolGuardV3.sol";

/// @title Transaction guard for Aave V3 L2 lending pool contract
contract AaveLendingPoolGuardV3L2Pool is AaveLendingPoolGuardV3 {
  /// @param poolManagerLogic the pool manager logic
  /// @param data the transaction data
  /// @return txType the transaction type of a given transaction data.
  /// @return isPublic if the transaction is public or private
  function txGuard(
    address poolManagerLogic,
    address to,
    bytes calldata data
  ) public view override returns (uint16 txType, bool isPublic) {
    bytes4 method = getMethod(data);
    address poolLogic = IPoolManagerLogic(poolManagerLogic).poolLogic();

    if (method == IL2Pool.supply.selector) {
      bytes32 args = abi.decode(getParams(data), (bytes32));
      (address depositAsset, , ) = decodeSupplyParams(args, IAaveV3Pool(to));

      txType = _supply(poolLogic, poolManagerLogic, to, depositAsset, poolLogic);
    } else if (method == IL2Pool.withdraw.selector) {
      bytes32 args = abi.decode(getParams(data), (bytes32));
      (address withdrawAsset, ) = decodeWithdrawParams(args, IAaveV3Pool(to));

      txType = _withdraw(poolLogic, poolManagerLogic, to, withdrawAsset, poolLogic);
    } else if (method == IL2Pool.setUserUseReserveAsCollateral.selector) {
      bytes32 args = abi.decode(getParams(data), (bytes32));
      (address asset, ) = decodeSetUserUseReserveAsCollateralParams(args, IAaveV3Pool(to));

      txType = _setUserUseReserveAsCollateral(poolManagerLogic, to, asset);
    } else if (method == IL2Pool.borrow.selector) {
      bytes32 args = abi.decode(getParams(data), (bytes32));
      (address borrowAsset, , , ) = decodeBorrowParams(args, IAaveV3Pool(to));

      txType = _borrow(poolLogic, poolManagerLogic, to, borrowAsset, poolLogic);
    } else if (method == IL2Pool.repay.selector || method == IL2Pool.repayWithATokens.selector) {
      bytes32 args = abi.decode(getParams(data), (bytes32));
      (address repayAsset, , ) = decodeRepayParams(args, IAaveV3Pool(to));

      txType = _repay(poolLogic, poolManagerLogic, to, repayAsset, poolLogic);
    } else {
      (txType, isPublic) = super.txGuard(poolManagerLogic, to, data);
    }
  }

  function afterTxGuard(address poolManagerLogic, address to, bytes memory data) external view override {
    bytes4 method = getMethod(data);

    if (
      method == IL2Pool.borrow.selector ||
      method == IL2Pool.setUserUseReserveAsCollateral.selector ||
      method == IL2Pool.withdraw.selector ||
      _canAffectHealthFactor(method)
    ) {
      _afterTxGuard(poolManagerLogic, to);
    }
  }

  // Calldata Logic from Aave V3 core - https://github.com/aave/aave-v3-core/blob/master/contracts/protocol/libraries/logic/CalldataLogic.sol

  /**
   * @notice Decodes compressed supply params to standard params
   * @param args The packed supply params
   * @return The address of the underlying reserve
   * @return The amount to supply
   * @return The referralCode
   */
  function decodeSupplyParams(bytes32 args, IAaveV3Pool lendingPool) internal view returns (address, uint256, uint16) {
    uint16 assetId;
    uint256 amount;
    uint16 referralCode;

    assembly {
      assetId := and(args, 0xFFFF)
      amount := and(shr(16, args), 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)
      referralCode := and(shr(144, args), 0xFFFF)
    }
    return (lendingPool.getReserveAddressById(assetId), amount, referralCode);
  }

  /**
   * @notice Decodes compressed withdraw params to standard params
   * @param args The packed withdraw params
   * @return The address of the underlying reserve
   * @return The amount to withdraw
   */
  function decodeWithdrawParams(bytes32 args, IAaveV3Pool lendingPool) internal view returns (address, uint256) {
    uint16 assetId;
    uint256 amount;
    assembly {
      assetId := and(args, 0xFFFF)
      amount := and(shr(16, args), 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)
    }
    if (amount == type(uint128).max) {
      amount = type(uint256).max;
    }
    return (lendingPool.getReserveAddressById(assetId), amount);
  }

  /**
   * @notice Decodes compressed borrow params to standard params
   * @param args The packed borrow params
   * @return The address of the underlying reserve
   * @return The amount to borrow
   * @return The interestRateMode, 1 for stable or 2 for variable debt
   * @return The referralCode
   */
  function decodeBorrowParams(
    bytes32 args,
    IAaveV3Pool lendingPool
  ) internal view returns (address, uint256, uint256, uint16) {
    uint16 assetId;
    uint256 amount;
    uint256 interestRateMode;
    uint16 referralCode;

    assembly {
      assetId := and(args, 0xFFFF)
      amount := and(shr(16, args), 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)
      interestRateMode := and(shr(144, args), 0xFF)
      referralCode := and(shr(152, args), 0xFFFF)
    }

    return (lendingPool.getReserveAddressById(assetId), amount, interestRateMode, referralCode);
  }

  /**
   * @notice Decodes compressed repay params to standard params
   * @param args The packed repay params
   * @return The address of the underlying reserve
   * @return The amount to repay
   * @return The interestRateMode, 1 for stable or 2 for variable debt
   */
  function decodeRepayParams(bytes32 args, IAaveV3Pool lendingPool) internal view returns (address, uint256, uint256) {
    uint16 assetId;
    uint256 amount;
    uint256 interestRateMode;

    assembly {
      assetId := and(args, 0xFFFF)
      amount := and(shr(16, args), 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)
      interestRateMode := and(shr(144, args), 0xFF)
    }

    if (amount == type(uint128).max) {
      amount = type(uint256).max;
    }

    return (lendingPool.getReserveAddressById(assetId), amount, interestRateMode);
  }

  /**
   * @notice Decodes compressed set user use reserve as collateral params to standard params
   * @param args The packed set user use reserve as collateral params
   * @return The address of the underlying reserve
   * @return True if to set using as collateral, false otherwise
   */
  function decodeSetUserUseReserveAsCollateralParams(
    bytes32 args,
    IAaveV3Pool lendingPool
  ) internal view returns (address, bool) {
    uint16 assetId;
    bool useAsCollateral;
    assembly {
      assetId := and(args, 0xFFFF)
      useAsCollateral := and(shr(16, args), 0x1)
    }
    return (lendingPool.getReserveAddressById(assetId), useAsCollateral);
  }
}
