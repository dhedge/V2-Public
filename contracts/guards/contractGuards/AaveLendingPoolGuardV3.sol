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
import "./AaveLendingPoolGuard.sol";

/// @title Transaction guard for Aave's lending pool contract
contract AaveLendingPoolGuardV3 is AaveLendingPoolGuard {
  using SafeMathUpgradeable for uint256;

  /// @notice Transaction guard for Aave Lending Pool
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
    virtual
    override
    returns (
      uint16 txType, // transaction type
      bool isPublic
    )
  {
    bytes4 method = getMethod(data);
    address poolLogic = IPoolManagerLogic(_poolManagerLogic).poolLogic();
    address factory = IPoolManagerLogic(_poolManagerLogic).factory();

    if (method == bytes4(keccak256("supply(address,uint256,address,uint16)"))) {
      (address depositAsset, uint256 amount, address onBehalfOf, ) = abi.decode(
        getParams(data),
        (address, uint256, address, uint16)
      );

      txType = _deposit(factory, poolLogic, _poolManagerLogic, to, depositAsset, amount, onBehalfOf);
    } else {
      (txType, isPublic) = super.txGuard(_poolManagerLogic, to, data);
    }
  }
}
