// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {ITxTrackingGuard} from "../../interfaces/guards/ITxTrackingGuard.sol";
import {IGuard} from "../../interfaces/guards/IGuard.sol";
import {IAaveV3Pool} from "../../interfaces/aave/v3/IAaveV3Pool.sol";
import {IPoolManagerLogic} from "../../interfaces/IPoolManagerLogic.sol";
import {AaveLendingPoolGuardV3} from "./AaveLendingPoolGuardV3.sol";

/// @title Transaction guard for Aave V3 L2 lending pool contract
contract AaveLendingPoolGuardV3L2Pool is AaveLendingPoolGuardV3, ITxTrackingGuard {
  uint256 public constant HEALTH_FACTOR_LOWER_BOUNDARY = 1.01e18; // Aave UI doesn't let withdrawal go through which leads to HF below 1.01

  bool public override isTxTrackingGuard = true;

  /// @notice Transaction guard for Aave V3 L2 Lending Pool
  /// @dev It supports Deposit, Withdraw, SetUserUseReserveAsCollateral, Borrow, Repay, swapBorrowRateMode, rebalanceStableBorrowRate functionality
  /// @param poolManagerLogic the pool manager logic
  /// @param data the transaction data
  /// @return txType the transaction type of a given transaction data.
  /// @return isPublic if the transaction is public or private
  function txGuard(
    address poolManagerLogic,
    address to,
    bytes calldata data
  ) public override(AaveLendingPoolGuardV3, IGuard) returns (uint16 txType, bool isPublic) {
    bytes4 method = getMethod(data);
    address poolLogic = IPoolManagerLogic(poolManagerLogic).poolLogic();
    address factory = IPoolManagerLogic(poolManagerLogic).factory();

    if (method == bytes4(keccak256("supply(bytes32)"))) {
      bytes32 args = abi.decode(getParams(data), (bytes32));
      (address depositAsset, uint256 amount, ) = decodeSupplyParams(args, IAaveV3Pool(to));

      txType = _deposit(factory, poolLogic, poolManagerLogic, to, depositAsset, amount, poolLogic);
    } else if (method == bytes4(keccak256("withdraw(bytes32)"))) {
      bytes32 args = abi.decode(getParams(data), (bytes32));
      (address withdrawAsset, uint256 amount) = decodeWithdrawParams(args, IAaveV3Pool(to));

      txType = _withdraw(factory, poolLogic, poolManagerLogic, to, withdrawAsset, amount, poolLogic);
    } else if (method == bytes4(keccak256("setUserUseReserveAsCollateral(bytes32)"))) {
      bytes32 args = abi.decode(getParams(data), (bytes32));
      (address asset, bool useAsCollateral) = decodeSetUserUseReserveAsCollateralParams(args, IAaveV3Pool(to));

      txType = _setUserUseReserveAsCollateral(factory, poolLogic, poolManagerLogic, to, asset, useAsCollateral);
    } else if (method == bytes4(keccak256("borrow(bytes32)"))) {
      bytes32 args = abi.decode(getParams(data), (bytes32));
      (address borrowAsset, uint256 amount, uint256 rateMode, ) = decodeBorrowParams(args, IAaveV3Pool(to));

      txType = _borrow(factory, poolLogic, poolManagerLogic, to, borrowAsset, amount, rateMode, poolLogic);
    } else if (method == bytes4(keccak256("repay(bytes32)"))) {
      bytes32 args = abi.decode(getParams(data), (bytes32));
      (address repayAsset, uint256 amount, ) = decodeRepayParams(args, IAaveV3Pool(to));

      txType = _repay(factory, poolLogic, poolManagerLogic, to, repayAsset, amount, poolLogic);
    } else if (method == bytes4(keccak256("swapBorrowRateMode(bytes32)"))) {
      bytes32 args = abi.decode(getParams(data), (bytes32));
      (address asset, uint256 rateMode) = decodeSwapBorrowRateModeParams(args, IAaveV3Pool(to));

      txType = _swapBorrowRateMode(factory, poolLogic, poolManagerLogic, to, asset, rateMode);
    } else if (method == bytes4(keccak256("rebalanceStableBorrowRate(bytes32)"))) {
      bytes32 args = abi.decode(getParams(data), (bytes32));
      (address asset, address user) = decodeRebalanceStableBorrowRateParams(args, IAaveV3Pool(to));

      txType = _rebalanceStableBorrowRate(factory, poolLogic, poolManagerLogic, to, asset, user);
    } else {
      (txType, isPublic) = super.txGuard(poolManagerLogic, to, data);
    }
  }

  function afterTxGuard(address poolManagerLogic, address to, bytes memory data) external view override {
    address poolLogic = IPoolManagerLogic(poolManagerLogic).poolLogic();

    bytes4 method = getMethod(data);

    // These are the actions which potentially can affect HF
    if (
      method == bytes4(keccak256("borrow(bytes32)")) ||
      method == bytes4(keccak256("setUserUseReserveAsCollateral(bytes32)")) ||
      method == bytes4(keccak256("withdraw(bytes32)")) ||
      method == bytes4(keccak256("borrow(address,uint256,uint256,uint16,address)")) ||
      method == bytes4(keccak256("setUserUseReserveAsCollateral(address,bool)")) ||
      method == bytes4(keccak256("withdraw(address,uint256,address)"))
    ) {
      (, , , , , uint256 healthFactor) = IAaveV3Pool(to).getUserAccountData(poolLogic);

      require(healthFactor > HEALTH_FACTOR_LOWER_BOUNDARY, "health factor too low");
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
   * @notice Decodes compressed swap borrow rate mode params to standard params
   * @param args The packed swap borrow rate mode params
   * @return The address of the underlying reserve
   * @return The interest rate mode, 1 for stable 2 for variable debt
   */
  function decodeSwapBorrowRateModeParams(
    bytes32 args,
    IAaveV3Pool lendingPool
  ) internal view returns (address, uint256) {
    uint16 assetId;
    uint256 interestRateMode;

    assembly {
      assetId := and(args, 0xFFFF)
      interestRateMode := and(shr(16, args), 0xFF)
    }

    return (lendingPool.getReserveAddressById(assetId), interestRateMode);
  }

  /**
   * @notice Decodes compressed rebalance stable borrow rate params to standard params
   * @param args The packed rabalance stable borrow rate params
   * @return The address of the underlying reserve
   * @return The address of the user to rebalance
   */
  function decodeRebalanceStableBorrowRateParams(
    bytes32 args,
    IAaveV3Pool lendingPool
  ) internal view returns (address, address) {
    uint16 assetId;
    address user;
    assembly {
      assetId := and(args, 0xFFFF)
      user := and(shr(16, args), 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)
    }
    return (lendingPool.getReserveAddressById(assetId), user);
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
