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

import "../../utils/TxDataUtils.sol";
import "../../interfaces/guards/IGuard.sol";
import "../../interfaces/IPoolManagerLogic.sol";
import "../../interfaces/IHasAssetInfo.sol";
import "../../interfaces/IHasSupportedAsset.sol";

/// @title Transaction guard for Aave V2 lending pool contract
contract AaveLendingPoolGuardV2 is TxDataUtils, IGuard {
  /// @notice Transaction guard for Aave V2 Lending Pool
  /// @dev It supports Withdraw, SetUserUseReserveAsCollateral, Repay, swapBorrowRateMode, rebalanceStableBorrowRate functionality
  /// @param _poolManagerLogic the pool manager logic
  /// @param data the transaction data
  /// @return txType the transaction type of a given transaction data.
  /// @return isPublic if the transaction is public or private
  function txGuard(
    address _poolManagerLogic,
    address to,
    bytes calldata data
  )
    external
    view
    override
    returns (
      uint16 txType, // transaction type
      bool // isPublic
    )
  {
    bytes4 method = getMethod(data);
    address poolLogic = IPoolManagerLogic(_poolManagerLogic).poolLogic();
    address factory = IPoolManagerLogic(_poolManagerLogic).factory();

    if (method == bytes4(keccak256("withdraw(address,uint256,address)"))) {
      (address withdrawAsset, , address onBehalfOf) = abi.decode(getParams(data), (address, uint256, address));

      txType = _withdraw(poolLogic, _poolManagerLogic, to, withdrawAsset, onBehalfOf);
    } else if (method == bytes4(keccak256("setUserUseReserveAsCollateral(address,bool)"))) {
      (address asset, ) = abi.decode(getParams(data), (address, bool));

      txType = _setUserUseReserveAsCollateral(factory, _poolManagerLogic, to, asset);
    } else if (method == bytes4(keccak256("repay(address,uint256,uint256,address)"))) {
      (address repayAsset, , , address onBehalfOf) = abi.decode(getParams(data), (address, uint256, uint256, address));

      txType = _repay(factory, poolLogic, _poolManagerLogic, to, repayAsset, onBehalfOf);
    } else if (method == bytes4(keccak256("swapBorrowRateMode(address,uint256)"))) {
      (address asset, uint256 rateMode) = abi.decode(getParams(data), (address, uint256));

      txType = _swapBorrowRateMode(_poolManagerLogic, asset, rateMode);
    } else if (method == bytes4(keccak256("rebalanceStableBorrowRate(address,address)"))) {
      (address asset, address user) = abi.decode(getParams(data), (address, address));

      txType = _rebalanceStableBorrowRate(poolLogic, _poolManagerLogic, asset, user);
    }

    return (txType, false);
  }

  function _withdraw(
    address poolLogic,
    address poolManagerLogic,
    address to,
    address withdrawAsset,
    address onBehalfOf
  ) internal view returns (uint16 txType) {
    IHasSupportedAsset poolManagerLogicAssets = IHasSupportedAsset(poolManagerLogic);

    require(poolManagerLogicAssets.isSupportedAsset(to), "aave not enabled");
    require(poolManagerLogicAssets.isSupportedAsset(withdrawAsset), "unsupported withdraw asset");

    require(onBehalfOf == poolLogic, "recipient is not pool");

    txType = 10; // Aave `Withdraw` type
  }

  function _setUserUseReserveAsCollateral(
    address factory,
    address poolManagerLogic,
    address to,
    address asset
  ) internal view returns (uint16 txType) {
    IHasSupportedAsset poolManagerLogicAssets = IHasSupportedAsset(poolManagerLogic);
    require(
      IHasAssetInfo(factory).getAssetType(asset) == 4 || IHasAssetInfo(factory).getAssetType(asset) == 14,
      "not borrow enabled"
    );
    require(poolManagerLogicAssets.isSupportedAsset(to), "aave not enabled");
    require(poolManagerLogicAssets.isSupportedAsset(asset), "unsupported asset");

    txType = 11; // Aave `SetUserUseReserveAsCollateral` type
  }

  function _repay(
    address factory,
    address poolLogic,
    address poolManagerLogic,
    address to,
    address repayAsset,
    address onBehalfOf
  ) internal view returns (uint16 txType) {
    IHasSupportedAsset poolManagerLogicAssets = IHasSupportedAsset(poolManagerLogic);

    require(poolManagerLogicAssets.isSupportedAsset(to), "aave not enabled");
    require(poolManagerLogicAssets.isSupportedAsset(repayAsset), "unsupported repay asset");
    require(
      IHasAssetInfo(factory).getAssetType(repayAsset) == 4 || IHasAssetInfo(factory).getAssetType(repayAsset) == 14,
      "not borrow enabled"
    );

    require(onBehalfOf == poolLogic, "recipient is not pool");

    txType = 13; // Aave `Repay` type
  }

  function _swapBorrowRateMode(
    address poolManagerLogic,
    address asset,
    uint256 rateMode
  ) internal view returns (uint16 txType) {
    require(rateMode == 1, "only variable rate"); // can swap only from stable to variable, not the other way around

    require(IHasSupportedAsset(poolManagerLogic).isSupportedAsset(asset), "unsupported asset");

    txType = 14; // Aave `SwapBorrowRateMode` type
  }

  function _rebalanceStableBorrowRate(
    address poolLogic,
    address poolManagerLogic,
    address asset,
    address user
  ) internal view returns (uint16 txType) {
    require(IHasSupportedAsset(poolManagerLogic).isSupportedAsset(asset), "unsupported asset");
    require(user == poolLogic, "user is not pool");

    txType = 15; // Aave `RebalanceStableBorrowRate` type
  }
}
