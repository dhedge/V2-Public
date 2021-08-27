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

// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import "./interfaces/IPoolLogic.sol";
import "./interfaces/IHasSupportedAsset.sol";
import "./interfaces/IHasPausable.sol";
import "./interfaces/IPoolManagerLogic.sol";
import "./interfaces/IHasGuardInfo.sol";
import "./interfaces/IHasGuardInfo.sol";
import "./interfaces/IPoolLogic.sol";
import "./interfaces/IERC20Extended.sol";
import "./interfaces/guards/IAssetGuard.sol";
import "./interfaces/aave/IAaveProtocolDataProvider.sol";
import "./interfaces/aave/ILendingPoolAddressesProvider.sol";
import "./interfaces/aave/IAToken.sol";

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";

/// @notice Logic implementation for tracking pool performance
contract PoolPerformance is OwnableUpgradeable {
  using SafeMathUpgradeable for uint256;

  mapping(address => mapping(address => uint256)) public internalBalancesMap;
  // Im keeping the `DirectDeposit`Factor naming for now, for continuity,
  // I will rename if we decide to adopt these changes
  // iDirectDepositFactor is the inverse of DirectDepositFactor in my other branches
  // It decreases the tokenPrice by directDeposit amounts
  mapping(address => uint256) public iDirectDepositFactorMap;

  IAaveProtocolDataProvider public aaveProtocolDataProvider;
  address public aaveLendingPool;

  /// @notice initialisation for the contract
  function initialize(address _aaveProtocolDataProvider) external initializer {
    __Ownable_init();

    aaveProtocolDataProvider = IAaveProtocolDataProvider(_aaveProtocolDataProvider);
    aaveLendingPool = ILendingPoolAddressesProvider(aaveProtocolDataProvider.ADDRESSES_PROVIDER()).getLendingPool();
  }

  function addAssetBalance(address asset, uint256 amount) external {
    address poolAddress = msg.sender;
    internalBalancesMap[poolAddress][asset] = internalBalancesMap[poolAddress][asset] + amount;
  }

  function hasDirectDeposit(address poolAddress) external view returns (bool) {
    address poolManagerAddress = IPoolLogic(poolAddress).poolManagerLogic();
    IHasSupportedAsset.Asset[] memory supportedAssets = IHasSupportedAsset(poolManagerAddress).getSupportedAssets();
    bool supportsAave = IHasSupportedAsset(poolManagerAddress).isSupportedAsset(aaveLendingPool);

    address aToken;

    for (uint8 i = 0; i < supportedAssets.length; i++) {
      address assetAddress = supportedAssets[i].asset;
      if (assetAddress != aaveLendingPool) {
        continue;
      }

      uint256 newBalance = IPoolManagerLogic(poolManagerAddress).assetBalance(assetAddress);

      // If the pool supports dai and aaveLendingPool, it also supports aDai so we must add that to our balance
      // Otherwise managers can direct desposit dai.
      if (supportsAave) {
        (aToken, , ) = IAaveProtocolDataProvider(aaveProtocolDataProvider).getReserveTokensAddresses(assetAddress);

        if (aToken != address(0)) {
          newBalance = newBalance + IAToken(aToken).scaledBalanceOf(poolAddress);
        }
      }

      if (internalBalancesMap[poolAddress][assetAddress] < newBalance) {
        return true;
      }
    }

    return false;
  }

  function getBalancesSnapshot(
    address poolManagerAddress,
    IHasSupportedAsset.Asset[] memory supportedAssets,
    bool supportsAave
  ) external view returns (uint256[] memory supportedAssetBalances) {
    address poolAddress = msg.sender;
    supportedAssetBalances = new uint256[](supportedAssets.length);
    address aToken;

    for (uint8 i = 0; i < supportedAssets.length; i++) {
      address assetAddress = supportedAssets[i].asset;
      if (assetAddress != aaveLendingPool) {
        continue;
      }

      uint256 newBalance = IPoolManagerLogic(poolManagerAddress).assetBalance(assetAddress);

      // If the pool supports dai and aaveLendingPool, it also supports aDai so we must add that to our balance
      // Otherwise managers can direct desposit dai.
      if (supportsAave) {
        (aToken, , ) = IAaveProtocolDataProvider(aaveProtocolDataProvider).getReserveTokensAddresses(assetAddress);

        if (aToken != address(0)) {
          newBalance = newBalance + IAToken(aToken).scaledBalanceOf(poolAddress);
        }
      }

      supportedAssetBalances[i] = newBalance;
    }
  }

  function updatedInternalBalancesByDiff(
    IHasSupportedAsset.Asset[] memory supportedAssets,
    uint256[] memory beforeSupportedAssetAmounts,
    uint256[] memory afterSupportedAssetAmounts
  ) external {
    address poolAddress = msg.sender;
    uint256 assetChange;
    for (uint8 i = 0; i < supportedAssets.length; i++) {
      assetChange = beforeSupportedAssetAmounts[i] - afterSupportedAssetAmounts[i];
      internalBalancesMap[poolAddress][supportedAssets[i].asset] =
        internalBalancesMap[poolAddress][supportedAssets[i].asset] -
        assetChange;
    }
  }

  function updateInternalBalances() external {
    _updateInternalBalances(msg.sender);
  }

  function _updateInternalBalances(address poolAddress) internal {
    address poolManagerAddress = IPoolLogic(poolAddress).poolManagerLogic();
    IHasSupportedAsset.Asset[] memory supportedAssets = IHasSupportedAsset(poolManagerAddress).getSupportedAssets();
    bool supportsAave = IHasSupportedAsset(poolManagerAddress).isSupportedAsset(aaveLendingPool);

    address aToken;

    for (uint8 i = 0; i < supportedAssets.length; i++) {
      address assetAddress = supportedAssets[i].asset;

      if (assetAddress != aaveLendingPool) {
        continue;
      }

      uint256 newBalance = IPoolManagerLogic(poolManagerAddress).assetBalance(assetAddress);

      // If the pool supports dai and aaveLendingPool, it also supports aDai so we must add that to our balance
      // Otherwise managers can direct desposit dai.
      if (supportsAave) {
        (aToken, , ) = IAaveProtocolDataProvider(aaveProtocolDataProvider).getReserveTokensAddresses(assetAddress);

        if (aToken != address(0)) {
          newBalance = newBalance + IAToken(aToken).scaledBalanceOf(poolAddress);
        }
      }

      internalBalancesMap[poolAddress][assetAddress] = newBalance;
    }
  }

  function tokenPriceAdjustedForPerformance(address poolAddress) public view returns (uint256) {
    return tokenPrice(poolAddress) * iDirectDepositFactorMap[poolAddress];
  }

  function tokenPriceAdjustedForPerformanceAndManagerFee(address poolAddress) public view returns (uint256) {
    uint256 currentTokenPrice = tokenPrice(poolAddress);
    uint256 feePerToken = IPoolLogic(poolAddress).availableManagerFee() / IERC20Extended(poolAddress).totalSupply();
    return (currentTokenPrice - feePerToken) * iDirectDepositFactorMap[poolAddress];
  }

  function tokenPrice(address poolAddress) public view returns (uint256) {
    return IPoolLogic(poolAddress).tokenPrice();
  }

  // We record the direct deposit value and subtract it from the token price later to get performance
  function recordDirectDepositValue(address poolAddress) public {
    address poolManagerAddress = IPoolLogic(poolAddress).poolManagerLogic();
    IHasSupportedAsset.Asset[] memory supportedAssets = IHasSupportedAsset(poolManagerAddress).getSupportedAssets();
    bool supportsAave = IHasSupportedAsset(poolManagerAddress).isSupportedAsset(aaveLendingPool);

    uint256 valueWithoutDirectDeposits = 0;

    address aToken;

    for (uint8 i = 0; i < supportedAssets.length; i++) {
      address assetAddress = supportedAssets[i].asset;
      if (assetAddress != aaveLendingPool) {
        continue;
      }

      // One thing to note here is that the impact of the direct deposits is variable
      // and is impacted by when this function is called and the price of the
      // direct deposited asset at the time not when the deposit happens
      uint256 amount = internalBalancesMap[poolAddress][assetAddress];
      valueWithoutDirectDeposits =
        valueWithoutDirectDeposits +
        IPoolManagerLogic(poolManagerAddress).assetValue(assetAddress, amount);

      // Once we record the internal value of the asset without direct deposits, we then update the internal balance to save on loops
      uint256 newBalance = IPoolManagerLogic(poolManagerAddress).assetBalance(assetAddress);

      // If the pool supports dai and aaveLendingPool, it also supports aDai so we must add that to our balance
      // Otherwise managers can direct desposit dai.
      if (supportsAave) {
        (aToken, , ) = IAaveProtocolDataProvider(aaveProtocolDataProvider).getReserveTokensAddresses(
          supportedAssets[i].asset
        );

        if (aToken != address(0)) {
          newBalance = newBalance + IAToken(aToken).scaledBalanceOf(poolAddress);
        }
      }

      internalBalancesMap[poolAddress][assetAddress] = newBalance;
    }

    if (iDirectDepositFactorMap[poolAddress] == 0) {
      iDirectDepositFactorMap[poolAddress] = 10**18;
    }

    uint256 totalFundValue = IPoolManagerLogic(poolManagerAddress).totalFundValue();
    // Combine the new factor with the oldfactor
    iDirectDepositFactorMap[poolAddress] = iDirectDepositFactorMap[poolAddress] =
      (iDirectDepositFactorMap[poolAddress] * valueWithoutDirectDeposits) /
      totalFundValue;
  }
}
