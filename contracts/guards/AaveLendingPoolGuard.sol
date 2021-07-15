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
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./IGuard.sol";
import "../utils/TxDataUtils.sol";
import "../interfaces/aave/IAaveProtocolDataProvider.sol";
import "../interfaces/IPoolManagerLogic.sol";
import "../interfaces/IHasGuardInfo.sol";
import "../interfaces/IManaged.sol";
import "../interfaces/IHasSupportedAsset.sol";

/// @title Transaction guard for Aave's lending pool contract
contract AaveLendingPoolGuard is TxDataUtils, IGuard {
  using SafeMathUpgradeable for uint256;

  event Deposit(address fundAddress, address asset, address lendingPool, uint256 amount, uint256 time);
  event Withdraw(address fundAddress, address asset, address lendingPool, uint256 amount, uint256 time);
  event SetUserUseReserveAsCollateral(address fundAddress, address asset, bool useAsCollateral, uint256 time);
  event Borrow(address fundAddress, address asset, address lendingPool, uint256 amount, uint256 time);
  event Repay(address fundAddress, address asset, address lendingPool, uint256 amount, uint256 time);
  event SwapBorrowRateMode(address fundAddress, address asset, uint256 rateMode);
  event RebalanceStableBorrowRate(address fundAddress, address asset);

  uint256 internal constant BORROWING_MASK = 0x5555555555555555555555555555555555555555555555555555555555555555;
  uint256 internal constant COLLATERAL_MASK = 0xAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA;

  /// @notice Transaction guard for Synthetix Exchanger
  /// @dev It supports Deposit, Withdraw, SetUserUseReserveAsCollateral, Borrow, Repay, swapBorrowRateMode, rebalanceStableBorrowRate functionality
  /// @param _poolManagerLogic the pool manager logic
  /// @param data the transaction data
  /// @return txType the transaction type of a given transaction data. 2 for `Exchange` type
  function txGuard(
    address _poolManagerLogic,
    address to, // to
    bytes calldata data
  )
    external
    override
    returns (
      uint16 txType // transaction type
    )
  {
    bytes4 method = getMethod(data);
    address poolLogic = IPoolManagerLogic(_poolManagerLogic).poolLogic();

    if (method == bytes4(keccak256("deposit(address,uint256,address,uint16)"))) {
      address depositAsset = convert32toAddress(getInput(data, 0));
      uint256 amount = uint256(getInput(data, 1));
      address onBehalfOf = convert32toAddress(getInput(data, 2));

      IHasSupportedAsset poolManagerLogicAssets = IHasSupportedAsset(_poolManagerLogic);

      require(poolManagerLogicAssets.isSupportedAsset(to), "aave not enabled");
      require(poolManagerLogicAssets.isSupportedAsset(depositAsset), "unsupported deposit asset");

      require(onBehalfOf == poolLogic, "recipient is not pool");

      emit Deposit(poolLogic, depositAsset, to, amount, block.timestamp);

      txType = 9; // Aave `Deposit` type
      return txType;
    } else if (method == bytes4(keccak256("withdraw(address,uint256,address)"))) {
      address withdrawAsset = convert32toAddress(getInput(data, 0));
      uint256 amount = uint256(getInput(data, 1));
      address onBehalfOf = convert32toAddress(getInput(data, 2));

      IHasSupportedAsset poolManagerLogicAssets = IHasSupportedAsset(_poolManagerLogic);

      require(poolManagerLogicAssets.isSupportedAsset(to), "aave not enabled");
      require(poolManagerLogicAssets.isSupportedAsset(withdrawAsset), "unsupported withdraw asset");

      require(onBehalfOf == poolLogic, "recipient is not pool");

      emit Withdraw(poolLogic, withdrawAsset, to, amount, block.timestamp);

      txType = 10; // Aave `Withdraw` type
      return txType;
    } else if (method == bytes4(keccak256("setUserUseReserveAsCollateral(address,bool)"))) {
      address asset = convert32toAddress(getInput(data, 0));
      bool useAsCollateral = uint256(getInput(data, 1)) != 0;

      IHasSupportedAsset poolManagerLogicAssets = IHasSupportedAsset(_poolManagerLogic);

      require(poolManagerLogicAssets.isSupportedAsset(to), "aave not enabled");
      require(poolManagerLogicAssets.isSupportedAsset(asset), "unsupported asset");

      emit SetUserUseReserveAsCollateral(poolLogic, asset, useAsCollateral, block.timestamp);

      txType = 11; // Aave `SetUserUseReserveAsCollateral` type
      return txType;
    } else if (method == bytes4(keccak256("borrow(address,uint256,uint256,uint16,address)"))) {
      address borrowAsset = convert32toAddress(getInput(data, 0));
      uint256 amount = uint256(getInput(data, 1));
      address onBehalfOf = convert32toAddress(getInput(data, 4));

      IHasSupportedAsset poolManagerLogicAssets = IHasSupportedAsset(_poolManagerLogic);

      require(poolManagerLogicAssets.isSupportedAsset(to), "aave not enabled");
      require(poolManagerLogicAssets.isSupportedAsset(borrowAsset), "unsupported borrow asset");

      require(poolManagerLogicAssets.isSupportedAsset(to), "aave not enabled");
      require(onBehalfOf == poolLogic, "recipient is not pool");

      // limit only one borrow asset
      IHasSupportedAsset.Asset[] memory supportedAssets = poolManagerLogicAssets.getSupportedAssets();
      uint256 length = supportedAssets.length;
      for (uint256 i = 0; i < length; i++) {
        if (supportedAssets[i].asset == borrowAsset) {
          continue;
        }

        // returns address(0) if it's not supported in aave
        address factory = IPoolManagerLogic(_poolManagerLogic).factory();
        address aaveProtocolDataProvider = IHasGuardInfo(factory).getAddress("aaveProtocolDataProvider");
        (, address stableDebtToken, address variableDebtToken) =
          IAaveProtocolDataProvider(aaveProtocolDataProvider).getReserveTokensAddresses(supportedAssets[i].asset);

        // check if asset is not supported or debt amount is zero
        require(
          (stableDebtToken == address(0) || IERC20(stableDebtToken).balanceOf(onBehalfOf) == 0) &&
            (variableDebtToken == address(0) || IERC20(variableDebtToken).balanceOf(onBehalfOf) == 0),
          "borrowing asset exists"
        );
      }

      emit Borrow(poolLogic, borrowAsset, to, amount, block.timestamp);

      txType = 12; // Aave `Borrow` type
      return txType;
    } else if (method == bytes4(keccak256("repay(address,uint256,uint256,address)"))) {
      address repayAsset = convert32toAddress(getInput(data, 0));
      uint256 amount = uint256(getInput(data, 1));
      address onBehalfOf = convert32toAddress(getInput(data, 3));

      IHasSupportedAsset poolManagerLogicAssets = IHasSupportedAsset(_poolManagerLogic);

      require(poolManagerLogicAssets.isSupportedAsset(to), "aave not enabled");
      require(poolManagerLogicAssets.isSupportedAsset(repayAsset), "unsupported repay asset");

      require(onBehalfOf == poolLogic, "recipient is not pool");

      emit Repay(poolLogic, repayAsset, to, amount, block.timestamp);

      txType = 13; // Aave `Repay` type
      return txType;
    } else if (method == bytes4(keccak256("swapBorrowRateMode(address,uint256)"))) {
      address asset = convert32toAddress(getInput(data, 0));
      uint256 rateMode = uint256(getInput(data, 1));

      IPoolManagerLogic poolManagerLogic = IPoolManagerLogic(_poolManagerLogic);
      IHasSupportedAsset poolManagerLogicAssets = IHasSupportedAsset(_poolManagerLogic);

      require(poolManagerLogicAssets.isSupportedAsset(asset), "unsupported asset");

      emit SwapBorrowRateMode(poolManagerLogic.poolLogic(), asset, rateMode);

      txType = 14; // Aave `SwapBorrowRateMode` type
    } else if (method == bytes4(keccak256("rebalanceStableBorrowRate(address,address)"))) {
      address asset = convert32toAddress(getInput(data, 0));
      address user = convert32toAddress(getInput(data, 1));

      IPoolManagerLogic poolManagerLogic = IPoolManagerLogic(_poolManagerLogic);
      IHasSupportedAsset poolManagerLogicAssets = IHasSupportedAsset(_poolManagerLogic);

      require(poolManagerLogicAssets.isSupportedAsset(asset), "unsupported asset");
      require(user == poolLogic, "user is not pool");

      emit RebalanceStableBorrowRate(poolManagerLogic.poolLogic(), asset);

      txType = 15; // Aave `RebalanceStableBorrowRate` type
    }
  }
}
