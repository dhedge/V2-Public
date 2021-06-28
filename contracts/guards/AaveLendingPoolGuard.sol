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

import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";

import "./IGuard.sol";
import "../utils/TxDataUtils.sol";
import "../interfaces/IPoolManagerLogic.sol";
import "../interfaces/IHasGuardInfo.sol";
import "../interfaces/IManaged.sol";
import "../interfaces/IHasSupportedAsset.sol";
import "../interfaces/aave/IAaveProtocolDataProvider.sol";

/// @title Transaction guard for Aave's lending pool contract
contract AaveLendingPoolGuard is TxDataUtils, IGuard {
  using SafeMathUpgradeable for uint256;

  event Deposit(address fundAddress, address asset, address lendingPool, uint256 amount, uint256 time);
  event Withdraw(address fundAddress, address asset, address lendingPool, uint256 amount, uint256 time);
  event SetUserUseReserveAsCollateral(address fundAddress, address asset, bool useAsCollateral, uint256 time);

  address public protocolDataProvider;

  constructor(address _protocolDataProvider) {
    protocolDataProvider = _protocolDataProvider;
  }

  /// @notice Transaction guard for Synthetix Exchanger
  /// @dev It supports Deposit, Withdraw, SetUserUseReserveAsCollateral, Borrow, Repay functionality
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
      uint8 txType // transaction type
    )
  {
    bytes4 method = getMethod(data);

    if (method == bytes4(keccak256("deposit(address,uint256,address,uint16)"))) {
      address depositAsset = convert32toAddress(getInput(data, 0));
      uint256 amount = uint256(getInput(data, 1));
      address onBehalfOf = convert32toAddress(getInput(data, 2));
      (address aToken, , ) = IAaveProtocolDataProvider(protocolDataProvider).getReserveTokensAddresses(depositAsset);

      IPoolManagerLogic poolManagerLogic = IPoolManagerLogic(_poolManagerLogic);
      IHasSupportedAsset poolManagerLogicAssets = IHasSupportedAsset(_poolManagerLogic);

      require(poolManagerLogicAssets.isSupportedAsset(depositAsset), "unsupported deposit asset");

      require(poolManagerLogicAssets.isSupportedAsset(aToken), "unsupported aave interest bearing token");

      require(onBehalfOf == poolManagerLogic.poolLogic(), "recipient is not pool");

      emit Deposit(poolManagerLogic.poolLogic(), depositAsset, to, amount, block.timestamp);

      txType = 9; // Aave `Deposit` type
      return txType;
    } else if (method == bytes4(keccak256("withdraw(address,uint256,address)"))) {
      address withdrawAsset = convert32toAddress(getInput(data, 0));
      uint256 amount = uint256(getInput(data, 1));
      address onBehalfOf = convert32toAddress(getInput(data, 2));
      (address aToken, , ) = IAaveProtocolDataProvider(protocolDataProvider).getReserveTokensAddresses(withdrawAsset);

      IPoolManagerLogic poolManagerLogic = IPoolManagerLogic(_poolManagerLogic);
      IHasSupportedAsset poolManagerLogicAssets = IHasSupportedAsset(_poolManagerLogic);

      require(poolManagerLogicAssets.isSupportedAsset(withdrawAsset), "unsupported withdraw asset");

      require(poolManagerLogicAssets.isSupportedAsset(aToken), "unsupported aave interest bearing token");

      require(onBehalfOf == poolManagerLogic.poolLogic(), "recipient is not pool");

      emit Withdraw(poolManagerLogic.poolLogic(), withdrawAsset, to, amount, block.timestamp);

      txType = 10; // Aave `Withdraw` type
      return txType;
    } else if (method == bytes4(keccak256("setUserUseReserveAsCollateral(address,bool)"))) {
      address asset = convert32toAddress(getInput(data, 0));
      (address aToken, , ) = IAaveProtocolDataProvider(protocolDataProvider).getReserveTokensAddresses(asset);
      bool useAsCollateral = uint256(getInput(data, 1)) != 0;

      IPoolManagerLogic poolManagerLogic = IPoolManagerLogic(_poolManagerLogic);
      IHasSupportedAsset poolManagerLogicAssets = IHasSupportedAsset(_poolManagerLogic);

      require(poolManagerLogicAssets.isSupportedAsset(asset), "unsupported asset");
      require(poolManagerLogicAssets.isSupportedAsset(aToken), "unsupported aave interest bearing token");

      emit SetUserUseReserveAsCollateral(poolManagerLogic.poolLogic(), asset, useAsCollateral, block.timestamp);

      txType = 11; // Aave `SetUserUseReserveAsCollateral` type
      return txType;
    }
  }
}
