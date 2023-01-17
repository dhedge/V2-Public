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
import "./AaveLendingPoolGuardV2.sol";

/// @title Transaction guard for Aave V3 lending pool contract
contract AaveLendingPoolGuardV3 is AaveLendingPoolGuardV2 {
  using SafeMathUpgradeable for uint256;

  /// @notice Transaction guard for Aave V3 Lending Pool
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

  // override borrow for aave v3
  function _borrow(
    address factory,
    address poolLogic,
    address poolManagerLogic,
    address to,
    address borrowAsset,
    uint256 amount,
    address onBehalfOf
  ) internal override returns (uint16 txType) {
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
    address aaveProtocolDataProviderV3 = IGovernance(governance).nameToDestination("aaveProtocolDataProviderV3");

    for (uint256 i = 0; i < supportedAssets.length; i++) {
      if (supportedAssets[i].asset == borrowAsset) {
        continue;
      }

      // returns address(0) if it's not supported in aave
      (, address stableDebtToken, address variableDebtToken) = IAaveProtocolDataProvider(aaveProtocolDataProviderV3)
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
}
