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

import "../../utils/TxDataUtils.sol";
import "../../interfaces/guards/IGuard.sol";
import "../../interfaces/aave/IAaveProtocolDataProvider.sol";
import "../../interfaces/IPoolManagerLogic.sol";
import "../../interfaces/IHasGuardInfo.sol";
import "../../interfaces/IHasAssetInfo.sol";
import "../../interfaces/IManaged.sol";
import "../../interfaces/IHasSupportedAsset.sol";
import "../../interfaces/IPoolFactory.sol";
import "../../interfaces/IGovernance.sol";

/// @title Transaction guard for Aave V2 lending pool contract
contract AaveLendingPoolGuardV2 is TxDataUtils, IGuard {
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

  /// @notice Transaction guard for Aave V2 Lending Pool
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
      bool // isPublic
    )
  {
    bytes4 method = getMethod(data);
    address poolLogic = IPoolManagerLogic(_poolManagerLogic).poolLogic();
    address factory = IPoolManagerLogic(_poolManagerLogic).factory();

    if (method == bytes4(keccak256("deposit(address,uint256,address,uint16)"))) {
      (address depositAsset, uint256 amount, address onBehalfOf, ) = abi.decode(
        getParams(data),
        (address, uint256, address, uint16)
      );

      txType = _deposit(factory, poolLogic, _poolManagerLogic, to, depositAsset, amount, onBehalfOf);
    } else if (method == bytes4(keccak256("withdraw(address,uint256,address)"))) {
      (address withdrawAsset, uint256 amount, address onBehalfOf) = abi.decode(
        getParams(data),
        (address, uint256, address)
      );

      txType = _withdraw(factory, poolLogic, _poolManagerLogic, to, withdrawAsset, amount, onBehalfOf);
    } else if (method == bytes4(keccak256("setUserUseReserveAsCollateral(address,bool)"))) {
      (address asset, bool useAsCollateral) = abi.decode(getParams(data), (address, bool));

      txType = _setUserUseReserveAsCollateral(factory, poolLogic, _poolManagerLogic, to, asset, useAsCollateral);
    } else if (method == bytes4(keccak256("borrow(address,uint256,uint256,uint16,address)"))) {
      (address borrowAsset, uint256 amount, uint256 rateMode, , address onBehalfOf) = abi.decode(
        getParams(data),
        (address, uint256, uint256, uint16, address)
      );

      txType = _borrow(factory, poolLogic, _poolManagerLogic, to, borrowAsset, amount, rateMode, onBehalfOf);
    } else if (method == bytes4(keccak256("repay(address,uint256,uint256,address)"))) {
      (address repayAsset, uint256 amount, , address onBehalfOf) = abi.decode(
        getParams(data),
        (address, uint256, uint256, address)
      );

      txType = _repay(factory, poolLogic, _poolManagerLogic, to, repayAsset, amount, onBehalfOf);
    } else if (method == bytes4(keccak256("swapBorrowRateMode(address,uint256)"))) {
      (address asset, uint256 rateMode) = abi.decode(getParams(data), (address, uint256));

      txType = _swapBorrowRateMode(factory, poolLogic, _poolManagerLogic, to, asset, rateMode);
    } else if (method == bytes4(keccak256("rebalanceStableBorrowRate(address,address)"))) {
      (address asset, address user) = abi.decode(getParams(data), (address, address));

      txType = _rebalanceStableBorrowRate(factory, poolLogic, _poolManagerLogic, to, asset, user);
    }

    return (txType, false);
  }

  function _deposit(
    address factory,
    address poolLogic,
    address poolManagerLogic,
    address to,
    address depositAsset,
    uint256 amount,
    address onBehalfOf
  ) internal returns (uint16 txType) {
    IHasSupportedAsset poolManagerLogicAssets = IHasSupportedAsset(poolManagerLogic);

    require(
      IHasAssetInfo(factory).getAssetType(depositAsset) == 4 || IHasAssetInfo(factory).getAssetType(depositAsset) == 14,
      "not lending enabled"
    );

    require(poolManagerLogicAssets.isSupportedAsset(to), "aave not enabled");
    require(poolManagerLogicAssets.isSupportedAsset(depositAsset), "unsupported deposit asset");

    require(onBehalfOf == poolLogic, "recipient is not pool");

    emit Deposit(poolLogic, depositAsset, to, amount, block.timestamp);

    txType = 9; // Aave `Deposit` type
  }

  function _withdraw(
    address, // factory
    address poolLogic,
    address poolManagerLogic,
    address to,
    address withdrawAsset,
    uint256 amount,
    address onBehalfOf
  ) internal returns (uint16 txType) {
    IHasSupportedAsset poolManagerLogicAssets = IHasSupportedAsset(poolManagerLogic);

    require(poolManagerLogicAssets.isSupportedAsset(to), "aave not enabled");
    require(poolManagerLogicAssets.isSupportedAsset(withdrawAsset), "unsupported withdraw asset");

    require(onBehalfOf == poolLogic, "recipient is not pool");

    emit Withdraw(poolLogic, withdrawAsset, to, amount, block.timestamp);

    txType = 10; // Aave `Withdraw` type
  }

  function _setUserUseReserveAsCollateral(
    address factory,
    address poolLogic,
    address poolManagerLogic,
    address to,
    address asset,
    bool useAsCollateral
  ) internal returns (uint16 txType) {
    IHasSupportedAsset poolManagerLogicAssets = IHasSupportedAsset(poolManagerLogic);
    require(
      IHasAssetInfo(factory).getAssetType(asset) == 4 || IHasAssetInfo(factory).getAssetType(asset) == 14,
      "not borrow enabled"
    );
    require(poolManagerLogicAssets.isSupportedAsset(to), "aave not enabled");
    require(poolManagerLogicAssets.isSupportedAsset(asset), "unsupported asset");

    emit SetUserUseReserveAsCollateral(poolLogic, asset, useAsCollateral, block.timestamp);

    txType = 11; // Aave `SetUserUseReserveAsCollateral` type
  }

  function _borrow(
    address factory,
    address poolLogic,
    address poolManagerLogic,
    address to,
    address borrowAsset,
    uint256 amount,
    uint256 rateMode,
    address onBehalfOf
  ) internal virtual returns (uint16 txType) {
    require(rateMode == 2, "only variable rate");

    require(
      IHasAssetInfo(factory).getAssetType(borrowAsset) == 4 || IHasAssetInfo(factory).getAssetType(borrowAsset) == 14,
      "not borrow enabled"
    );
    require(IHasSupportedAsset(poolManagerLogic).isSupportedAsset(to), "aave not enabled");
    require(IHasSupportedAsset(poolManagerLogic).isSupportedAsset(borrowAsset), "unsupported borrow asset");

    require(onBehalfOf == poolLogic, "recipient is not pool");

    // limit only one borrow asset
    IHasSupportedAsset.Asset[] memory supportedAssets = IHasSupportedAsset(poolManagerLogic).getSupportedAssets();
    address governance = IPoolFactory(factory).governanceAddress();
    address aaveProtocolDataProviderV2 = IGovernance(governance).nameToDestination("aaveProtocolDataProviderV2");

    for (uint256 i = 0; i < supportedAssets.length; i++) {
      if (supportedAssets[i].asset == borrowAsset) {
        continue;
      }

      // returns address(0) if it's not supported in aave
      (, address stableDebtToken, address variableDebtToken) = IAaveProtocolDataProvider(aaveProtocolDataProviderV2)
        .getReserveTokensAddresses(supportedAssets[i].asset);

      // check if asset is not supported or debt amount is zero
      require(
        (stableDebtToken == address(0) || IERC20(stableDebtToken).balanceOf(onBehalfOf) == 0) &&
          (variableDebtToken == address(0) || IERC20(variableDebtToken).balanceOf(onBehalfOf) == 0),
        "borrowing asset exists"
      );
    }

    emit Borrow(poolLogic, borrowAsset, to, amount, block.timestamp);

    txType = 12; // Aave `Borrow` type
  }

  function _repay(
    address factory,
    address poolLogic,
    address poolManagerLogic,
    address to,
    address repayAsset,
    uint256 amount,
    address onBehalfOf
  ) internal returns (uint16 txType) {
    IHasSupportedAsset poolManagerLogicAssets = IHasSupportedAsset(poolManagerLogic);

    require(poolManagerLogicAssets.isSupportedAsset(to), "aave not enabled");
    require(poolManagerLogicAssets.isSupportedAsset(repayAsset), "unsupported repay asset");
    require(
      IHasAssetInfo(factory).getAssetType(repayAsset) == 4 || IHasAssetInfo(factory).getAssetType(repayAsset) == 14,
      "not borrow enabled"
    );

    require(onBehalfOf == poolLogic, "recipient is not pool");

    emit Repay(poolLogic, repayAsset, to, amount, block.timestamp);

    txType = 13; // Aave `Repay` type
  }

  function _swapBorrowRateMode(
    address, // factory
    address, // poolLogic
    address poolManagerLogic,
    address, // to
    address asset,
    uint256 rateMode
  ) internal returns (uint16 txType) {
    require(rateMode == 1, "only variable rate"); // can swap only from stable to variable, not the other way around

    require(IHasSupportedAsset(poolManagerLogic).isSupportedAsset(asset), "unsupported asset");

    emit SwapBorrowRateMode(IPoolManagerLogic(poolManagerLogic).poolLogic(), asset, rateMode);

    txType = 14; // Aave `SwapBorrowRateMode` type
  }

  function _rebalanceStableBorrowRate(
    address, // factory
    address poolLogic,
    address poolManagerLogic,
    address, // to
    address asset,
    address user
  ) internal returns (uint16 txType) {
    require(IHasSupportedAsset(poolManagerLogic).isSupportedAsset(asset), "unsupported asset");
    require(user == poolLogic, "user is not pool");

    emit RebalanceStableBorrowRate(IPoolManagerLogic(poolManagerLogic).poolLogic(), asset);

    txType = 15; // Aave `RebalanceStableBorrowRate` type
  }
}
