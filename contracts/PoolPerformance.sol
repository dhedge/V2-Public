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
import "./interfaces/IPoolLogic.sol";
import "./interfaces/IERC20Extended.sol";

import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

/// @notice Logic implementation for tracking pool performance
contract PoolPerformance is PausableUpgradeable {
  using SafeMathUpgradeable for uint256;

  mapping(address => mapping(address => uint256)) public internalBalancesMap;
  // Im keeping the `DirectDeposit`Factor naming for now, for continuity,
  // I will rename if we decide to adopt these changes
  // iDirectDepositFactor is the inverse of DirectDepositFactor in my other branches
  // It decreases the tokenPrice by directDeposit amounts
  mapping(address => uint256) public iDirectDepositFactorMap;

  // Not sure about the visibility of this one
  // Other
  function initialize() external initializer {
    __Pausable_init();
  }

  function addAssetBalance(address poolAddress, address asset, uint256 amount) external {
    // Should we check poolAddress is one of our pools?
    require(msg.sender == poolAddress, "only pool");
    internalBalancesMap[poolAddress][asset] = internalBalancesMap[poolAddress][asset] + amount;
  }

  function subtractAssetBalance(address poolAddress, address asset, uint256 amount) external {
    // Should we check poolAddress is one of our pools?
    require(msg.sender == poolAddress, "only pool");
    internalBalancesMap[poolAddress][asset] = internalBalancesMap[poolAddress][asset] - amount;
  }

  function hasDirectDeposit(address poolAddress) external view returns (bool) {
    address poolManagerAddress = IPoolLogic(poolAddress).poolManagerLogic();
    IHasSupportedAsset.Asset[] memory supportedAssets = IHasSupportedAsset(poolManagerAddress).getSupportedAssets();
    uint256 assetCount = supportedAssets.length;

    for (uint8 i = 0; i < assetCount; i++) {
      // Again not super keen on this circular reference from poolAddress to manager to poolAddress
      if (internalBalancesMap[poolAddress][supportedAssets[i].asset] < IPoolManagerLogic(poolManagerAddress).assetBalance(supportedAssets[i].asset)) {
        return true;
      }
    }
    return false;
  }

  function updateInternalBalances(address poolAddress, uint16 txType) external {
    require(msg.sender == poolAddress, "only pool");
    // Lecky suggested that we store a list of txTypes that require us to update the balances
    // This is a smart optimisation but have not implemented it yet for brevity.

    // check txType requires updating balances

    _updateInternalBalances(poolAddress);
  }

  function _updateInternalBalances(address poolAddress) internal {
    // Should this be pausible?
    //require(!paused(), "contracts paused");
    address poolManagerAddress = IPoolLogic(poolAddress).poolManagerLogic();
    IHasSupportedAsset.Asset[] memory supportedAssets = IHasSupportedAsset(poolManagerAddress).getSupportedAssets();
    uint256 assetCount = supportedAssets.length;

    for (uint8 i = 0; i < assetCount; i++) {
      // The call here is a bit cicular, because assetBalance gets the balance for the poolAddress not sure I like this.
      internalBalancesMap[poolAddress][supportedAssets[i].asset] = IPoolManagerLogic(poolManagerAddress).assetBalance(supportedAssets[i].asset);
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
  // Might need to be marked as non-reentrant
  function recordDirectDepositValue(address poolAddress) public {
    // Should we check poolAddress is one of our pools?
    require(msg.sender == poolAddress, "only pool");

    address poolManagerAddress = IPoolLogic(poolAddress).poolManagerLogic();
    IHasSupportedAsset.Asset[] memory supportedAssets = IHasSupportedAsset(poolManagerAddress).getSupportedAssets();
    uint256 assetCount = supportedAssets.length;

    uint256 valueWithoutDirectDeposits = 0;

    for (uint8 i = 0; i < assetCount; i++) {
      address assetAddress = supportedAssets[i].asset;
      uint256 amount = internalBalancesMap[poolAddress][assetAddress];
      valueWithoutDirectDeposits = valueWithoutDirectDeposits + IPoolManagerLogic(poolManagerAddress)
        .assetValue(assetAddress, amount);
    }

    if (iDirectDepositFactorMap[poolAddress] == 0) {
      iDirectDepositFactorMap[poolAddress] = 10 ** 18;
    }

    uint256 totalFundValue = IPoolManagerLogic(poolManagerAddress).totalFundValue();
    // Calculate what portion of the value is not from directDeposits (i.e %90 i.e 0.9)
    uint256 additionalIDirectDepositFactor = (totalFundValue - valueWithoutDirectDeposits) / totalFundValue;
    // totalFundValue = 100, PreviousIDirectDepositFactor = 0.9, AdditionalIDirectDepositFactor = 0.7
    // newDirectDepositFactor = (100 * 0.9 * 0.7) / 100 = 0.63 (ie. 0.37 i.e 37% of the funds value is front direct deposits)
    // We need to combine the previous directDepositFactor and the additional directDepositFactor
    iDirectDepositFactorMap[poolAddress] = (totalFundValue * iDirectDepositFactorMap[poolAddress] * additionalIDirectDepositFactor) / totalFundValue;
    // once we have recorded the direct deposit value change we can reset our internalBalances
    _updateInternalBalances(poolAddress);
  }

}
