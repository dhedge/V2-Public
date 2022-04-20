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
// Copyright (c) 2021 dHEDGE DAO
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//
// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";

import "../../interfaces/IPoolManagerLogic.sol";
import "../../interfaces/aave/v3/ILendingL2Pool.sol";
import "./AaveLendingPoolGuardV3.sol";

/// @title Transaction guard for Aave V3 L2 lending pool contract
contract AaveLendingPoolGuardV3L2Pool is AaveLendingPoolGuardV3 {
  using SafeMathUpgradeable for uint256;

  ILendingL2Pool public lendingPool;

  constructor(address _lendingPool) {
    lendingPool = ILendingL2Pool(_lendingPool);
  }

  /// @notice Transaction guard for Aave V3 L2 Lending Pool
  /// @dev It supports Deposit, Withdraw, SetUserUseReserveAsCollateral, Borrow, Repay, swapBorrowRateMode, rebalanceStableBorrowRate functionality
  /// @param _poolManagerLogic the pool manager logic
  /// @param data the transaction data
  /// @return txType the transaction type of a given transaction data.
  /// @return isPublic if the transaction is public or private
  function txGuard(
    address _poolManagerLogic,
    address to,
    bytes calldata data
  )
    public
    override
    returns (
      uint16 txType, // transaction type
      bool isPublic
    )
  {
    bytes4 method = getMethod(data);
    address poolLogic = IPoolManagerLogic(_poolManagerLogic).poolLogic();
    address factory = IPoolManagerLogic(_poolManagerLogic).factory();

    if (method == bytes4(keccak256("supply(bytes32)"))) {
      bytes32 args = abi.decode(getParams(data), (bytes32));
      (address depositAsset, uint256 amount, ) = decodeSupplyParams(args);

      txType = _deposit(factory, poolLogic, _poolManagerLogic, to, depositAsset, amount, poolLogic);
    } else if (method == bytes4(keccak256("withdraw(bytes32)"))) {
      bytes32 args = abi.decode(getParams(data), (bytes32));
      (address withdrawAsset, uint256 amount) = decodeWithdrawParams(args);

      txType = _withdraw(factory, poolLogic, _poolManagerLogic, to, withdrawAsset, amount, poolLogic);
    } else if (method == bytes4(keccak256("setUserUseReserveAsCollateral(bytes32)"))) {
      bytes32 args = abi.decode(getParams(data), (bytes32));
      (address asset, bool useAsCollateral) = decodeSetUserUseReserveAsCollateralParams(args);

      txType = _setUserUseReserveAsCollateral(factory, poolLogic, _poolManagerLogic, to, asset, useAsCollateral);
    } else if (method == bytes4(keccak256("borrow(bytes32)"))) {
      bytes32 args = abi.decode(getParams(data), (bytes32));
      (address borrowAsset, uint256 amount, , ) = decodeBorrowParams(args);

      txType = _borrow(factory, poolLogic, _poolManagerLogic, to, borrowAsset, amount, poolLogic);
    } else if (method == bytes4(keccak256("repay(bytes32)"))) {
      bytes32 args = abi.decode(getParams(data), (bytes32));
      (address repayAsset, uint256 amount, ) = decodeRepayParams(args);

      txType = _repay(factory, poolLogic, _poolManagerLogic, to, repayAsset, amount, poolLogic);
    } else if (method == bytes4(keccak256("swapBorrowRateMode(bytes32)"))) {
      bytes32 args = abi.decode(getParams(data), (bytes32));
      (address asset, uint256 rateMode) = decodeSwapBorrowRateModeParams(args);

      txType = _swapBorrowRateMode(factory, poolLogic, _poolManagerLogic, to, asset, rateMode);
    } else if (method == bytes4(keccak256("rebalanceStableBorrowRate(bytes32)"))) {
      bytes32 args = abi.decode(getParams(data), (bytes32));
      (address asset, address user) = decodeRebalanceStableBorrowRateParams(args);

      txType = _rebalanceStableBorrowRate(factory, poolLogic, _poolManagerLogic, to, asset, user);
    } else {
      (txType, isPublic) = super.txGuard(_poolManagerLogic, to, data);
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
  function decodeSupplyParams(bytes32 args)
    internal
    view
    returns (
      address,
      uint256,
      uint16
    )
  {
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
  function decodeWithdrawParams(bytes32 args) internal view returns (address, uint256) {
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
  function decodeBorrowParams(bytes32 args)
    internal
    view
    returns (
      address,
      uint256,
      uint256,
      uint16
    )
  {
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
  function decodeRepayParams(bytes32 args)
    internal
    view
    returns (
      address,
      uint256,
      uint256
    )
  {
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
  function decodeSwapBorrowRateModeParams(bytes32 args) internal view returns (address, uint256) {
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
  function decodeRebalanceStableBorrowRateParams(bytes32 args) internal view returns (address, address) {
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
  function decodeSetUserUseReserveAsCollateralParams(bytes32 args) internal view returns (address, bool) {
    uint16 assetId;
    bool useAsCollateral;
    assembly {
      assetId := and(args, 0xFFFF)
      useAsCollateral := and(shr(16, args), 0x1)
    }
    return (lendingPool.getReserveAddressById(assetId), useAsCollateral);
  }
}
