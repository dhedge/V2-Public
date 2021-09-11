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
import "./interfaces/aave/ILendingPool.sol";
import "./interfaces/aave/ILendingPoolAddressesProvider.sol";
import "./interfaces/aave/IAToken.sol";

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";

/// @notice Logic implementation for tracking pool performance
contract PoolPerformance is OwnableUpgradeable {
  using SafeMathUpgradeable for uint256;

  mapping(address => mapping(address => uint256)) public internalBalancesMap;

  uint256 public constant DENOMINATOR = 10**18;
  // Stores the internal value ratio numerator
  mapping(address => uint256) public internalValueFactorMap;

  IAaveProtocolDataProvider public aaveProtocolDataProvider;
  address public aaveLendingPool;


  /// @notice initialisation for the contract
  function initialize(address _aaveProtocolDataProvider) external initializer {
    __Ownable_init();

    aaveProtocolDataProvider = IAaveProtocolDataProvider(_aaveProtocolDataProvider);
    aaveLendingPool = ILendingPoolAddressesProvider(aaveProtocolDataProvider.ADDRESSES_PROVIDER()).getLendingPool();
  }

  /// @notice returns the realtime value of a pool token adjusted for any external value
  /// @param poolAddress The address of the pool
  /// @return the value per token that only includes the increase in value of the underlying pool assets
  function tokenPriceAdjustedForPerformance(address poolAddress) public view returns (uint256) {
    return tokenPrice(poolAddress).mul(externalValuePerToken(poolAddress)).div(DENOMINATOR);
  }

  /// @notice returns the realtime value of a pool token adjusted for any external value and manager fee
  /// @param poolAddress The address of the pool
  /// @return the value per token that only includes the increase in value of the underlying pool assets, sans manager fee
  function tokenPriceAdjustedForPerformanceAndManagerFee(address poolAddress) public view returns (uint256) {
    return tokenPriceAdjustedForManagerFee(poolAddress).mul(externalValuePerToken(poolAddress)).div(DENOMINATOR);
  }

  /// @notice returns the realtime value of a pool tokens underlying value, sans any manager fee
  /// @dev this is the value per token the owner receives on withdraw.
  /// @param poolAddress The address of the pool
  /// @return the value per token, sans manager fee, received by the user on withdraw.
  function tokenPriceAdjustedForManagerFee(address poolAddress) public view returns (uint256) {
    uint256 currentTokenPrice = tokenPrice(poolAddress);
    return
      currentTokenPrice.mul(IERC20Extended(poolAddress).totalSupply()).div(
        IERC20Extended(poolAddress).totalSupply().add(IPoolLogic(poolAddress).availableManagerFee())
      );
  }

  /// @notice returns the realtime value of a pool tokens underlying value
  /// @dev this value does not include any reductions for unpaid manager fees that maybe saught on withdraw
  /// @param poolAddress The address of the pool
  /// @return the value per token of all the underlying pool assets.
  function tokenPrice(address poolAddress) public view returns (uint256) {
    return IPoolLogic(poolAddress).tokenPrice();
  }

  /// @notice a view function that returns the realtime + recorded difference between internal and external value of a token
  /// @param poolAddress The address of the pool
  /// @return the value per token of airdrops and other external value
  function externalValuePerToken(address poolAddress) public view returns (uint256) {
    address poolManagerAddress = IPoolLogic(poolAddress).poolManagerLogic();
    IHasSupportedAsset.Asset[] memory supportedAssets = IHasSupportedAsset(poolManagerAddress).getSupportedAssets();

    uint256 internalValue = 0;
    uint256 externalValue = 0;

    address aToken;

    for (uint8 i = 0; i < supportedAssets.length; i++) {
      address assetAddress = supportedAssets[i].asset;
      if (assetAddress == aaveLendingPool) {
        continue;
      }

      uint256 externalBalance = IPoolManagerLogic(poolManagerAddress).assetBalance(assetAddress);
      // If the pool supports dai and aaveLendingPool, it also supports aDai so we must track that too
      // i.e dai === aDai.
      if (IHasSupportedAsset(poolManagerAddress).isSupportedAsset(aaveLendingPool)) {
        (aToken, , ) = IAaveProtocolDataProvider(aaveProtocolDataProvider).getReserveTokensAddresses(assetAddress);

        if (aToken != address(0)) {
          externalBalance = externalBalance.add(IAToken(aToken).scaledBalanceOf(poolAddress));
        }
      }

      externalValue = externalValue.add(
        IPoolManagerLogic(poolManagerAddress).assetValue(assetAddress, externalBalance)
      );
      // if supportsAAVE
      // Get normal balance
      // get aToken scaledBalance
      // combine and get assetValue

      internalValue = internalValue.add(
        IPoolManagerLogic(poolManagerAddress).assetValue(assetAddress, internalBalancesMap[poolAddress][assetAddress])
      );
    }

    if (internalValueFactorMap[poolAddress] == 0) {
      return internalValue.mul(DENOMINATOR).div(externalValue);
    } else {
      return
        internalValueFactorMap[poolAddress].mul(internalValue.mul(DENOMINATOR).div(externalValue)).div(DENOMINATOR);
    }
  }

  /// @notice Records the difference in value between the internal balances and the external balances of a pool
  /// @dev The value recorded is per token, it resets the internal balances to equal external balances once recorded.
  /// @param poolAddress The address of the pool
  function recordExternalValue(address poolAddress) public {
    address poolManagerAddress = IPoolLogic(poolAddress).poolManagerLogic();
    IHasSupportedAsset.Asset[] memory supportedAssets = IHasSupportedAsset(poolManagerAddress).getSupportedAssets();
    bool supportsAave = IHasSupportedAsset(poolManagerAddress).isSupportedAsset(aaveLendingPool);

    uint256 internalValue = 0;
    uint256 externalValue = 0;

    address aToken;

    for (uint8 i = 0; i < supportedAssets.length; i++) {
      address assetAddress = supportedAssets[i].asset;
      if (assetAddress == aaveLendingPool) {
        continue;
      }
      // This is the same as what IPoolManagerLogic.totalFundValue().
      externalValue = externalValue.add(IPoolManagerLogic(poolManagerAddress).assetValue(assetAddress));

      // One thing to note here is that the impact of the external value is variable
      // and is impacted by when this function is called and the price of the
      // external asset at the time.
      internalValue = internalValue.add(
        IPoolManagerLogic(poolManagerAddress).assetValue(assetAddress, internalBalancesMap[poolAddress][assetAddress])
      );

      // Once we record the current value of the internal asset, we then update the internal balance to equal the external balance
      uint256 externalBalance = IPoolManagerLogic(poolManagerAddress).assetBalance(assetAddress);

      // If the pool supports dai and aaveLendingPool, it also supports aDai so we must track that too
      // i.e dai === aDai.
      if (supportsAave) {
        (aToken, , ) = IAaveProtocolDataProvider(aaveProtocolDataProvider).getReserveTokensAddresses(assetAddress);

        if (aToken != address(0)) {
          externalBalance = externalBalance.add(IAToken(aToken).scaledBalanceOf(poolAddress));
        }
      }

      internalBalancesMap[poolAddress][assetAddress] = externalBalance;
    }

    // In most cases this will be true, and when it is, there is no externalValue to record so we exit early
    if (internalValue == externalValue) {
      return;
    }

    if (internalValueFactorMap[poolAddress] == 0) {
      internalValueFactorMap[poolAddress] = internalValue.mul(DENOMINATOR).div(externalValue);
    } else {
      internalValueFactorMap[poolAddress] = internalValueFactorMap[poolAddress]
        .mul(internalValue.mul(DENOMINATOR).div(externalValue))
        .div(DENOMINATOR);
    }
  }

  /// @notice Increase the internal balanace of the given asset
  /// @dev Used for including new deposits in the internal balance
  /// @param asset The address of the asset
  /// @param amount The amount of the asset
  function addAssetBalance(address asset, uint256 amount) external {
    address poolAddress = msg.sender;
    internalBalancesMap[poolAddress][asset] = internalBalancesMap[poolAddress][asset].add(amount);
  }

  /// @notice Checks to see if the external balances of a pool are greater than the internal balances
  /// @dev Only currently used in tests, Originally used to stop pool actions before recording air drops.
  /// @param poolAddress The address of the pool
  /// @return true if the pool has external balances
  function hasExternalBalances(address poolAddress) public view returns (bool) {
    address poolManagerAddress = IPoolLogic(poolAddress).poolManagerLogic();
    IHasSupportedAsset.Asset[] memory supportedAssets = IHasSupportedAsset(poolManagerAddress).getSupportedAssets();
    bool supportsAave = IHasSupportedAsset(poolManagerAddress).isSupportedAsset(aaveLendingPool);

    address aToken;

    for (uint8 i = 0; i < supportedAssets.length; i++) {
      address assetAddress = supportedAssets[i].asset;
      if (assetAddress == aaveLendingPool) {
        continue;
      }

      uint256 externalBalance = IPoolManagerLogic(poolManagerAddress).assetBalance(assetAddress);

      // If the pool supports dai and aaveLendingPool, it also supports aDai so we must track that too
      // i.e dai === aDai.
      if (supportsAave) {
        (aToken, , ) = IAaveProtocolDataProvider(aaveProtocolDataProvider).getReserveTokensAddresses(assetAddress);

        if (aToken != address(0)) {
          externalBalance = externalBalance.add(IAToken(aToken).scaledBalanceOf(poolAddress));
        }
      }

      if (internalBalancesMap[poolAddress][assetAddress] < externalBalance) {
        return true;
      }
    }

    return false;
  }

  /// @notice Takes a snapshot of a pools external balances
  /// @dev The parameters could be simplified to only the poolAddress but we pass the following for performance
  /// @param poolManagerAddress The address of the poolManager for the pool that we want to snapshot
  /// @param supportedAssets The supportedAssets of the pool that we want to snapshot
  /// @return supportedAssetBalances a list of balances of the supported assets passed in, in order
  function getBalancesSnapshot(address poolManagerAddress, IHasSupportedAsset.Asset[] memory supportedAssets)
    external
    view
    returns (uint256[] memory supportedAssetBalances)
  {
    address poolAddress = msg.sender;
    supportedAssetBalances = new uint256[](supportedAssets.length);
    bool supportsAave = IHasSupportedAsset(poolManagerAddress).isSupportedAsset(aaveLendingPool);
    address aToken;

    for (uint8 i = 0; i < supportedAssets.length; i++) {
      address assetAddress = supportedAssets[i].asset;
      if (assetAddress == aaveLendingPool) {
        continue;
      }

      uint256 externalBalance = IPoolManagerLogic(poolManagerAddress).assetBalance(assetAddress);

      // If the pool supports dai and aaveLendingPool, it also supports aDai so we must track that too
      // i.e dai === aDai.
      if (supportsAave) {
        (aToken, , ) = IAaveProtocolDataProvider(aaveProtocolDataProvider).getReserveTokensAddresses(assetAddress);

        if (aToken != address(0)) {
          externalBalance = externalBalance.add(IAToken(aToken).scaledBalanceOf(poolAddress));
        }
      }

      supportedAssetBalances[i] = externalBalance;
    }
  }

  /// @notice Takes two snapshots created from getBalancesSnapshot and update the internal balances based on the difference
  /// @dev We use this to determine the change of a pools balance by any transaction we don't know the specific outcome of
  /// @param supportedAssets A list of the pools supportedAssets (passed in for performance)
  /// @param beforeSupportedAssetBalances List of balances of the supported assets (in order)
  /// @param afterSupportedAssetBalances List of balances of the supported assets (in order)
  function updatedInternalBalancesByDiff(
    IHasSupportedAsset.Asset[] memory supportedAssets,
    uint256[] memory beforeSupportedAssetBalances,
    uint256[] memory afterSupportedAssetBalances
  ) external {
    address poolAddress = msg.sender;
    uint256 assetChange;
    for (uint8 i = 0; i < supportedAssets.length; i++) {
      assetChange = beforeSupportedAssetBalances[i].sub(afterSupportedAssetBalances[i]);
      internalBalancesMap[poolAddress][supportedAssets[i].asset] =
        internalBalancesMap[poolAddress][supportedAssets[i].asset] -
        assetChange;
    }
  }

  /// @notice Resets the internal balances to equal the external balances
  /// @dev Used to update the internal balances after a manager executes a transaction/s should only be called by the pool
  function updateInternalBalances() external {
    _updateInternalBalances(msg.sender);
  }

  /// @notice Resets the internal balances to equal the external balances
  /// @dev Used to update the internal balances after a manager executes a transaction/s
  /// @param poolAddress The address of the pool we're updating the balances of
  function _updateInternalBalances(address poolAddress) internal {
    address poolManagerAddress = IPoolLogic(poolAddress).poolManagerLogic();
    IHasSupportedAsset.Asset[] memory supportedAssets = IHasSupportedAsset(poolManagerAddress).getSupportedAssets();
    bool supportsAave = IHasSupportedAsset(poolManagerAddress).isSupportedAsset(aaveLendingPool);

    address aToken;

    for (uint8 i = 0; i < supportedAssets.length; i++) {
      address assetAddress = supportedAssets[i].asset;

      if (assetAddress == aaveLendingPool) {
        continue;
      }

      uint256 externalBalance = IPoolManagerLogic(poolManagerAddress).assetBalance(assetAddress);

      // If the pool supports dai and aaveLendingPool, it also supports aDai so we must track that too
      // i.e dai === aDai.
      if (supportsAave) {
        (aToken, , ) = IAaveProtocolDataProvider(aaveProtocolDataProvider).getReserveTokensAddresses(assetAddress);

        if (aToken != address(0)) {
          externalBalance = externalBalance.add(IAToken(aToken).scaledBalanceOf(poolAddress));
        }
      }

      internalBalancesMap[poolAddress][assetAddress] = externalBalance;
    }
  }

  function setExternalValue(address poolAddress, uint256 value) public onlyOwner {
    internalValueFactorMap[poolAddress] = value;
  }
}
