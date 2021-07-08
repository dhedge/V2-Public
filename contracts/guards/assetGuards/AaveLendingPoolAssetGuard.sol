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

import "./ERC20Guard.sol";
import "./IAaveLendingPoolAssetGuard.sol";
import "../../interfaces/aave/ILendingPool.sol";
import "../../interfaces/aave/IAaveProtocolDataProvider.sol";
import "../../interfaces/aave/ILendingPoolAddressesProvider.sol";
import "../../interfaces/IAssetHandler.sol";
import "../../interfaces/IHasSupportedAsset.sol";
import "../../interfaces/IPoolLogic.sol";

/// @title Aave lending pool asset guard
/// @dev Asset type = 3
contract AaveLendingPoolAssetGuard is TxDataUtils, ERC20Guard, IAaveLendingPoolAssetGuard {
  using SafeMathUpgradeable for uint256;

  // For Aave decimal calculation
  uint256 constant DECIMALS_MASK = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF00FFFFFFFFFFFF;
  uint256 constant RESERVE_DECIMALS_START_BIT_POSITION = 48;

  IAaveProtocolDataProvider public aaveProtocolDataProvider;
  ILendingPoolAddressesProvider public aaveAddressProvider;
  ILendingPool public aaveLendingPool;
  IAssetHandler public assetHandler;
  address public override sushiswapRouter;

  constructor(address _aaveProtocolDataProvider, address _sushiswapRouter, address _assetHandler) {
    aaveProtocolDataProvider = IAaveProtocolDataProvider(_aaveProtocolDataProvider);
    aaveAddressProvider = ILendingPoolAddressesProvider(aaveProtocolDataProvider.ADDRESSES_PROVIDER());
    aaveLendingPool = ILendingPool(aaveAddressProvider.getLendingPool());
    sushiswapRouter = _sushiswapRouter;
    assetHandler = IAssetHandler(_assetHandler);
  }

  /// @notice Returns the pool position of Aave lending pool
  /// @dev Returns the balance priced in ETH
  /// @param pool The pool logic address
  function getBalance(address pool, address) public view override returns (uint256 balance) {
    IHasSupportedAsset poolManagerLogicAssets = IHasSupportedAsset(IPoolLogic(pool).poolManagerLogic());
    IHasSupportedAsset.Asset[] memory supportedAssets = poolManagerLogicAssets.getSupportedAssets();

    address asset;
    uint256 decimals;
    uint256 tokenUnit;
    uint256 tokenPriceInUsd;
    uint256 collateralBalance;
    uint256 debtBalance;
    uint256 totalCollateralInUsd;
    uint256 totalDebtInUsd;

    uint256 length = supportedAssets.length;
    for (uint256 i = 0; i < length; i++) {
      asset = supportedAssets[i].asset;

      (collateralBalance, debtBalance, decimals) = _calculateAaveBalance(pool, asset);

      if (collateralBalance != 0 || debtBalance != 0) {
        tokenUnit = 10**decimals;
        tokenPriceInUsd = assetHandler.getUSDPrice(asset);
        totalCollateralInUsd = totalCollateralInUsd.add(tokenPriceInUsd.mul(collateralBalance).div(tokenUnit));
        totalDebtInUsd = totalDebtInUsd.add(tokenPriceInUsd.mul(debtBalance).div(tokenUnit));
      }
    }

    balance = totalCollateralInUsd.sub(totalDebtInUsd);
  }

  /// @notice Returns the decimal
  function getDecimals(address) external pure override returns (uint256 decimals) {
    decimals = 18;
  }

  /// @notice Creates transaction data for withdrawing tokens
  /// @dev Withdrawal processing is not applicable for this guard
  /// @return withdrawAsset and
  /// @return withdrawBalance are used to withdraw portion of asset balance to investor
  /// @return withdrawContract and
  /// @return txData are used to execute the withdrawal transaction in PoolLogic
  function withdrawProcessing(
    address pool, // pool
    address, // asset
    uint256 portion, // portion
    address // to
  )
    external
    virtual
    override
    returns (
      address withdrawAsset,
      uint256 withdrawBalance,
      address withdrawContract,
      bytes memory txData
    )
  {
    (address[] memory collateralAssets, uint256[] memory amounts) = _calculateCollateralAssets(pool);
    (address borrowAsset, uint256 borrowAmount, uint256 interestRateMode) = _calculateBorrowAsset(pool);
    uint256 portionOfAmount = borrowAmount.mul(portion).div(10**18);

    withdrawAsset = borrowAsset;
    withdrawContract = address(aaveLendingPool);

    bytes memory params = abi.encode(interestRateMode, collateralAssets, amounts, portion);
    txData = _prepareFlashLoan(pool, withdrawAsset, portionOfAmount, params);

    return (withdrawAsset, withdrawBalance, withdrawContract, txData);
  }

  function _calculateAaveBalance(address pool, address asset)
    internal
    view
    returns (
      uint256 collateralBalance,
      uint256 debtBalance,
      uint256 decimals
    )
  {
    (address aToken, address stableDebtToken, address variableDebtToken) =
      aaveProtocolDataProvider.getReserveTokensAddresses(asset);
    if (aToken != address(0)) {
      collateralBalance = IERC20(aToken).balanceOf(pool);
      debtBalance = IERC20(stableDebtToken).balanceOf(pool).add(IERC20(variableDebtToken).balanceOf(pool));
    }

    ILendingPool.ReserveConfigurationMap memory configuration = aaveLendingPool.getConfiguration(asset);
    decimals = (configuration.data & ~DECIMALS_MASK) >> RESERVE_DECIMALS_START_BIT_POSITION;
  }

  function _calculateCollateralAssets(address pool)
    internal
    view
    returns (
      address[] memory collateralAssets,
      uint256[] memory amounts
    )
  {
    IHasSupportedAsset poolManagerLogicAssets = IHasSupportedAsset(IPoolLogic(pool).poolManagerLogic());
    IHasSupportedAsset.Asset[] memory supportedAssets = poolManagerLogicAssets.getSupportedAssets();
    address aToken;
    uint256 length = supportedAssets.length;
    uint256[] memory _amounts = new uint256[](length);
    uint256 collateralAssetCount = 0;
    for (uint256 i = 0; i < length; i++) {
      (aToken, , ) = IAaveProtocolDataProvider(aaveProtocolDataProvider)
        .getReserveTokensAddresses(supportedAssets[i].asset);

      if (aToken != address(0)) {
        _amounts[i] = IERC20(aToken).balanceOf(pool);
        if (_amounts[i] != 0) {
          collateralAssetCount = collateralAssetCount.add(1);
        }
      }
    }

    collateralAssets = new address[](collateralAssetCount);
    amounts = new uint256[](collateralAssetCount);
    uint256 index = 0;
    for (uint256 i = 0; i < length; i++) {
      if (_amounts[i] != 0) {
        collateralAssets[index] = supportedAssets[i].asset;
        amounts[index] = _amounts[i];
        index = index.add(1);
      }
    }
  }

  function _calculateBorrowAsset(address pool)
    internal
    view
    returns (
      address asset,
      uint256 amount,
      uint256 interestRateMode
    )
  {
    IHasSupportedAsset poolManagerLogicAssets = IHasSupportedAsset(IPoolLogic(pool).poolManagerLogic());
    IHasSupportedAsset.Asset[] memory supportedAssets = poolManagerLogicAssets.getSupportedAssets();
    address stableDebtToken;
    address variableDebtToken;
    uint256 length = supportedAssets.length;
    for (uint256 i = 0; i < length; i++) {
      // returns address(0) if it's not supported in aave
      (, stableDebtToken, variableDebtToken) = IAaveProtocolDataProvider(aaveProtocolDataProvider)
        .getReserveTokensAddresses(supportedAssets[i].asset);

      if (stableDebtToken != address(0) && IERC20(stableDebtToken).balanceOf(pool) != 0) {
        asset = supportedAssets[i].asset;
        amount = IERC20(stableDebtToken).balanceOf(pool);
        interestRateMode = 1;

        break;
      }
      if (variableDebtToken != address(0) && IERC20(variableDebtToken).balanceOf(pool) != 0) {
        asset = supportedAssets[i].asset;
        amount = IERC20(variableDebtToken).balanceOf(pool);
        interestRateMode = 2;

        break;
      }
    }
  }

  function _prepareFlashLoan(address pool, address asset, uint256 amount, bytes memory params) internal pure returns(bytes memory txData) {
    address[] memory assets = new address[](1);
    assets[0] = asset;
    uint256[] memory amounts = new uint256[](1);
    amounts[0] = amount;
    uint256[] memory modes = new uint256[](1);
    modes[0] = 0;

    txData = abi.encodeWithSelector(
      bytes4(keccak256("flashLoan(address,address[],uint256[],uint256[],address,bytes,uint16)")),
      pool, //receiverAddress
      assets,
      amounts,
      modes,
      pool, // onBehalfOf
      params,
      0 // referralCode
    );
  }
}
