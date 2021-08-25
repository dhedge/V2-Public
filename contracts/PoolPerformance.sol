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

  /// @notice initialisation for the contract
  function initialize() external initializer {
    __Ownable_init();
  }

  function addAssetBalance(address asset, uint256 amount) external {
    address poolAddress = msg.sender;
    internalBalancesMap[poolAddress][asset] = internalBalancesMap[poolAddress][asset] + amount;
  }

  function hasDirectDeposit(address poolAddress) external view returns (bool) {
    address poolManagerAddress = IPoolLogic(poolAddress).poolManagerLogic();
    IHasSupportedAsset.Asset[] memory supportedAssets = IHasSupportedAsset(poolManagerAddress).getSupportedAssets();

    uint256[] memory supportedAssetAmounts = getBalancesSnapshot(poolAddress, supportedAssets);
    for (uint8 i = 0; i < supportedAssets.length; i++) {
      if (internalBalancesMap[poolAddress][supportedAssets[i].asset] < supportedAssetAmounts[i]) {
        return true;
      }
    }
    return false;
  }

  function getBalancesSnapshot(address poolAddress, IHasSupportedAsset.Asset[] memory supportedAssets)
    public
    view
    returns (uint256[] memory supportedAssetAmounts)
  {
    supportedAssetAmounts = new uint256[](supportedAssets.length);

    for (uint8 i = 0; i < supportedAssets.length; i++) {
      address guard = IHasGuardInfo(poolFactory).getAssetGuard(supportedAssets[i].asset);
      // Need to check here that the guard exists and that it has getPrincipalBalances?
      (uint256 amount, uint256[] memory sAamounts) =
        IAssetGuard(guard).getPrincipalBalances(poolAddress, supportedAssets[i].asset, supportedAssets);

      supportedAssetAmounts[i] = supportedAssetAmounts[i] + amount;

      for (uint8 y = 0; i < sAamounts.length; y++) {
        supportedAssetAmounts[y] = supportedAssetAmounts[y] + sAamounts[y];
      }
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
    uint256[] memory supportedAssetAmountsSnapshot = getBalancesSnapshot(poolAddress, supportedAssets);
    for (uint8 i = 0; i < supportedAssets.length; i++) {
      internalBalancesMap[poolAddress][supportedAssets[i].asset] = supportedAssetAmountsSnapshot[i];
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

    uint256 valueWithoutDirectDeposits = 0;

    for (uint8 i = 0; i < supportedAssets.length; i++) {
      address assetAddress = supportedAssets[i].asset;
      uint256 amount = internalBalancesMap[poolAddress][assetAddress];

      // One thing to note here is that the impact of the direct deposits is variable
      // and is impacted by when this function is called and the price of the
      // direct deposited asset at the time not when the deposit happens
      valueWithoutDirectDeposits =
        valueWithoutDirectDeposits +
        IPoolManagerLogic(poolManagerAddress).assetValue(assetAddress, amount);
    }

    if (iDirectDepositFactorMap[poolAddress] == 0) {
      iDirectDepositFactorMap[poolAddress] = 10**18;
    }

    uint256 totalFundValue = IPoolManagerLogic(poolManagerAddress).totalFundValue();
    // Combine the new factor with the oldfactor
    iDirectDepositFactorMap[poolAddress] = iDirectDepositFactorMap[poolAddress] =
      (iDirectDepositFactorMap[poolAddress] * valueWithoutDirectDeposits) /
      totalFundValue;
    // once we have recorded the direct deposit value change we can reset our internalBalances
    _updateInternalBalances(poolAddress);
  }
}
