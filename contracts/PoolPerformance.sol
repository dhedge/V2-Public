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
import "./interfaces/IGovernance.sol";
import "./interfaces/IHasSupportedAsset.sol";
import "./interfaces/IHasPausable.sol";
import "./interfaces/IPoolManagerLogic.sol";
import "./interfaces/IPoolFactory.sol";
import "./interfaces/IHasGuardInfo.sol";
import "./interfaces/IHasAssetInfo.sol";
import "./interfaces/IPoolLogic.sol";
import "./interfaces/IERC20Extended.sol";
import "./interfaces/guards/IAssetGuard.sol";
import "./interfaces/aave/IAaveProtocolDataProvider.sol";
import "./interfaces/aave/v2/ILendingPool.sol";
import "./interfaces/aave/v2/ILendingPoolAddressesProvider.sol";
import "./interfaces/aave/v3/IPoolAddressesProvider.sol";
import "./interfaces/aave/IAToken.sol";

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";

/// @notice Logic implementation for tracking pool performance
contract PoolPerformance is OwnableUpgradeable {
  using SafeMathUpgradeable for uint256;

  struct InternalExternalValue {
    uint256 internalValue;
    uint256 externalValue;
  }

  struct AaveAddresses {
    address aaveProtocolDataProvider;
    address aaveLendingPool;
    bool supportsAave;
  }

  mapping(address => bool) public poolInitialized;
  mapping(address => mapping(address => uint256)) public internalBalancesMap;

  uint256 public constant DENOMINATOR = 10**18;
  // Stores the internal value ratio numerator
  mapping(address => uint256) public internalValueFactorMap;

  bool public enabled;

  modifier isEnabled() {
    if (enabled) {
      _;
    }
  }

  /// @notice initialisation for the contract
  function initialize() external initializer {
    __Ownable_init();
  }

  /// @notice returns the realtime value of a pool token adjusted for any external value
  /// @param poolAddress The address of the pool
  /// @return the value per token that only includes the increase in value of the underlying pool assets
  function tokenPriceAdjustedForPerformance(address poolAddress) external view returns (uint256) {
    uint256 currentTokenPrice = tokenPrice(poolAddress);
    if (currentTokenPrice == 0) {
      return 0;
    }
    return currentTokenPrice.mul(realtimeInternalValueFactor(poolAddress)).div(DENOMINATOR);
  }

  /// @notice returns the realtime value of a pool tokens underlying value
  /// @dev this value does not include any reductions for unpaid manager fees that maybe saught on withdraw
  /// @param poolAddress The address of the pool
  /// @return the value per token of all the underlying pool assets.
  function tokenPriceWithoutManagerFee(address poolAddress) public view returns (uint256) {
    return IPoolLogic(poolAddress).tokenPriceWithoutManagerFee();
  }

  /// @notice returns the realtime value of a pool tokens underlying value adjusted for any manager fee
  /// @dev this value does include any reductions for unpaid manager fees that maybe saught on withdraw
  /// @param poolAddress The address of the pool
  /// @return the value per token of all the underlying pool assets.
  function tokenPrice(address poolAddress) public view returns (uint256) {
    return IPoolLogic(poolAddress).tokenPrice();
  }

  /// @notice a view function that returns recorded difference between internal and external value of a token
  /// @param poolAddress The address of the pool
  /// @return the factor per token of airdrops and other external value raised by the denominator
  function internalValueFactor(address poolAddress) external view returns (uint256) {
    if (internalValueFactorMap[poolAddress] == 0) {
      return DENOMINATOR;
    } else {
      return internalValueFactorMap[poolAddress];
    }
  }

  /// @notice a view function that returns the realtime + recorded difference between internal and external value of a token
  /// @param poolAddress The address of the pool
  /// @return the value per token of airdrops and other external value
  function realtimeInternalValueFactor(address poolAddress) public view returns (uint256) {
    if (!poolInitialized[poolAddress]) {
      return DENOMINATOR;
    }

    address poolManagerAddress = IPoolLogic(poolAddress).poolManagerLogic();
    IHasSupportedAsset.Asset[] memory supportedAssets = IHasSupportedAsset(poolManagerAddress).getSupportedAssets();
    AaveAddresses memory aaveAddresses = _getAaveLendingPoolAndDataProvider(poolAddress);

    InternalExternalValue memory internalExternalValue = InternalExternalValue(0, 0);

    address aToken;
    for (uint8 i = 0; i < supportedAssets.length; i++) {
      address assetAddress = supportedAssets[i].asset;
      // AaveLendingPool or Univ3Lp
      if (
        IHasAssetInfo(IPoolLogic(poolAddress).factory()).getAssetType(assetAddress) == 3 ||
        IHasAssetInfo(IPoolLogic(poolAddress).factory()).getAssetType(assetAddress) == 7
      ) {
        continue;
      }

      uint256 externalBalance = IPoolManagerLogic(poolManagerAddress).assetBalance(assetAddress);
      // If the pool supports dai and aaveLendingPool, it also supports aDai so we must track that too
      // i.e dai === aDai.
      if (
        aaveAddresses.supportsAave && IHasAssetInfo(IPoolLogic(poolAddress).factory()).getAssetType(assetAddress) == 4
      ) {
        (aToken, , ) = IAaveProtocolDataProvider(aaveAddresses.aaveProtocolDataProvider).getReserveTokensAddresses(
          assetAddress
        );

        if (aToken != address(0)) {
          externalBalance = externalBalance.add(IAToken(aToken).scaledBalanceOf(poolAddress));
        }
      }

      internalExternalValue.externalValue = internalExternalValue.externalValue.add(
        IPoolManagerLogic(poolManagerAddress).assetValue(assetAddress, externalBalance)
      );

      internalExternalValue.internalValue = internalExternalValue.internalValue.add(
        IPoolManagerLogic(poolManagerAddress).assetValue(assetAddress, internalBalancesMap[poolAddress][assetAddress])
      );
    }

    if (internalValueFactorMap[poolAddress] == 0) {
      return internalExternalValue.internalValue.mul(DENOMINATOR).div(internalExternalValue.externalValue);
    } else {
      return
        internalValueFactorMap[poolAddress]
          .mul(internalExternalValue.internalValue.mul(DENOMINATOR).div(internalExternalValue.externalValue))
          .div(DENOMINATOR);
    }
  }

  /// @notice Records the difference in value between the internal balances and the external balances of a pool
  /// @dev The value recorded is per token, it resets the internal balances to equal external balances once recorded.
  /// @param poolAddress The address of the pool
  function recordExternalValue(address poolAddress) external isEnabled {
    if (!poolInitialized[poolAddress]) {
      _updateInternalBalances(poolAddress);
      poolInitialized[poolAddress] = true;
      return;
    }

    if (!hasExternalBalances(poolAddress)) {
      return;
    }

    address poolManagerAddress = IPoolLogic(poolAddress).poolManagerLogic();
    IHasSupportedAsset.Asset[] memory supportedAssets = IHasSupportedAsset(poolManagerAddress).getSupportedAssets();
    AaveAddresses memory aaveAddresses = _getAaveLendingPoolAndDataProvider(poolAddress);

    InternalExternalValue memory internalExternalValue = InternalExternalValue(0, 0);

    address aToken;

    for (uint8 i = 0; i < supportedAssets.length; i++) {
      address assetAddress = supportedAssets[i].asset;
      uint16 assetType = IHasAssetInfo(IPoolLogic(poolAddress).factory()).getAssetType(assetAddress);
      // AaveLendingPool or Univ3Lp
      if (assetType == 3 || assetType == 7) {
        continue;
      }
      // One thing to note here is that the impact of the external value is variable
      // and is impacted by when this function is called and the price of the
      // external asset at the time.
      internalExternalValue.internalValue = internalExternalValue.internalValue.add(
        IPoolManagerLogic(poolManagerAddress).assetValue(assetAddress, internalBalancesMap[poolAddress][assetAddress])
      );

      // Once we record the current value of the internal asset, we then update the internal balance to equal the external balance
      uint256 externalBalance = IPoolManagerLogic(poolManagerAddress).assetBalance(assetAddress);
      // If the pool supports dai and aaveLendingPool, it also supports aDai so we must track that too
      // i.e dai === aDai.
      if (aaveAddresses.supportsAave && assetType == 4) {
        (aToken, , ) = IAaveProtocolDataProvider(aaveAddresses.aaveProtocolDataProvider).getReserveTokensAddresses(
          assetAddress
        );

        if (aToken != address(0)) {
          externalBalance = externalBalance.add(IAToken(aToken).scaledBalanceOf(poolAddress));
        }
      }

      internalExternalValue.externalValue = internalExternalValue.externalValue.add(
        IPoolManagerLogic(poolManagerAddress).assetValue(assetAddress, externalBalance)
      );

      if (internalBalancesMap[poolAddress][assetAddress] != externalBalance) {
        internalBalancesMap[poolAddress][assetAddress] = externalBalance;
      }
    }

    // In most cases this will be true, and when it is, there is no internalExternalValue.externalValue to record so we exit early
    if (internalExternalValue.externalValue <= internalExternalValue.internalValue) {
      return;
    }

    if (internalValueFactorMap[poolAddress] == 0) {
      internalValueFactorMap[poolAddress] = internalExternalValue.internalValue.mul(DENOMINATOR).div(
        internalExternalValue.externalValue
      );
    } else {
      internalValueFactorMap[poolAddress] = internalValueFactorMap[poolAddress]
        .mul(internalExternalValue.internalValue.mul(DENOMINATOR).div(internalExternalValue.externalValue))
        .div(DENOMINATOR);
    }
  }

  /// @notice Increase/decrease the internal balanace of the given asset
  /// @dev Used for including new deposits in the internal balance
  /// @param asset The address of the asset
  /// @param plusAmount The increased amount of the asset
  /// @param minusAmount The decreased amount of the asset
  function changeAssetBalance(
    address asset,
    uint256 plusAmount,
    uint256 minusAmount
  ) external isEnabled {
    address poolAddress = msg.sender;
    if (!poolInitialized[poolAddress]) {
      _updateInternalBalances(poolAddress);
      poolInitialized[poolAddress] = true;
      return;
    }

    internalBalancesMap[poolAddress][asset] = internalBalancesMap[poolAddress][asset].add(plusAmount).sub(minusAmount);
  }

  /// @notice Checks to see if the external balances of a pool are greater than the internal balances
  /// @dev Only currently used in tests, Originally used to stop pool actions before recording air drops.
  /// @param poolAddress The address of the pool
  /// @return true if the pool has external balances
  function hasExternalBalances(address poolAddress) public view returns (bool) {
    if (!poolInitialized[poolAddress]) {
      return false;
    }

    address poolManagerAddress = IPoolLogic(poolAddress).poolManagerLogic();
    IHasSupportedAsset.Asset[] memory supportedAssets = IHasSupportedAsset(poolManagerAddress).getSupportedAssets();
    AaveAddresses memory aaveAddresses = _getAaveLendingPoolAndDataProvider(poolAddress);

    address aToken;

    for (uint8 i = 0; i < supportedAssets.length; i++) {
      address assetAddress = supportedAssets[i].asset;
      uint16 assetType = IHasAssetInfo(IPoolLogic(poolAddress).factory()).getAssetType(assetAddress);
      // AaveLendingPool or Univ3Lp
      if (assetType == 3 || assetType == 7) {
        continue;
      }

      uint256 externalBalance = IPoolManagerLogic(poolManagerAddress).assetBalance(assetAddress);

      // If the pool supports dai and aaveLendingPool, it also supports aDai so we must track that too
      // i.e dai === aDai.
      if (aaveAddresses.supportsAave && assetType == 4) {
        (aToken, , ) = IAaveProtocolDataProvider(aaveAddresses.aaveProtocolDataProvider).getReserveTokensAddresses(
          assetAddress
        );

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

  /// @notice Set the internal value factor of a pool
  /// @dev Used for governance updates if pool is airdropped value
  /// @param poolAddress The address of the pool
  /// @param newInternalValueFactor 10 ** 18 is 100%;
  function setInternalValueFactor(address poolAddress, uint256 newInternalValueFactor) external onlyOwner {
    internalValueFactorMap[poolAddress] = newInternalValueFactor;
  }

  /// @notice resets the internal value factor of a pool
  /// @dev Used if all a pools value is withdrawn
  function resetInternalValueFactor() external {
    address poolAddress = msg.sender;
    internalValueFactorMap[poolAddress] = DENOMINATOR;
  }

  /// @notice adjusts the factor by the factor between a and b
  /// @dev Used for including new deposits in the internal balance
  /// @param a numerator
  /// @param b The amount its being allocated over
  function adjustInternalValueFactor(uint256 a, uint256 b) external isEnabled {
    address poolAddress = msg.sender;
    if (internalValueFactorMap[poolAddress] == 0) {
      internalValueFactorMap[poolAddress] = DENOMINATOR.mul(b.sub(a)).div(b);
    } else {
      internalValueFactorMap[poolAddress] = internalValueFactorMap[poolAddress].mul(b.sub(a)).div(b);
    }
  }

  /// @notice Resets the internal balances to equal the external balances
  /// @dev Used to update the internal balances after a manager executes a transaction/s should only be called by the pool
  function updateInternalBalances() external isEnabled {
    _updateInternalBalances(msg.sender);
  }

  /// @notice Sets the pool as initialized
  /// @dev Should only be called when creating an empty pool
  function initializePool() external isEnabled {
    poolInitialized[msg.sender] = true;
  }

  /// @notice Resets the internal balances to equal the external balances
  /// @dev Used to update the internal balances after a manager executes a transaction/s
  /// @param poolAddress The address of the pool we're updating the balances of
  function _updateInternalBalances(address poolAddress) internal {
    address poolManagerAddress = IPoolLogic(poolAddress).poolManagerLogic();
    IHasSupportedAsset.Asset[] memory supportedAssets = IHasSupportedAsset(poolManagerAddress).getSupportedAssets();
    AaveAddresses memory aaveAddresses = _getAaveLendingPoolAndDataProvider(poolAddress);

    address aToken;

    for (uint8 i = 0; i < supportedAssets.length; i++) {
      address assetAddress = supportedAssets[i].asset;
      uint16 assetType = IHasAssetInfo(IPoolLogic(poolAddress).factory()).getAssetType(assetAddress);
      // AaveLendingPool or Univ3Lp
      if (assetType == 3 || assetType == 7) {
        continue;
      }

      uint256 externalBalance = IPoolManagerLogic(poolManagerAddress).assetBalance(assetAddress);

      // If the pool supports dai and aaveLendingPool, it also supports aDai so we must track that too
      // i.e dai === aDai.
      if (aaveAddresses.supportsAave && assetType == 4) {
        (aToken, , ) = IAaveProtocolDataProvider(aaveAddresses.aaveProtocolDataProvider).getReserveTokensAddresses(
          assetAddress
        );

        if (aToken != address(0)) {
          externalBalance = externalBalance.add(IAToken(aToken).scaledBalanceOf(poolAddress));
        }
      }

      internalBalancesMap[poolAddress][assetAddress] = externalBalance;
    }
  }

  function _getAaveLendingPoolAndDataProvider(address poolAddress)
    internal
    view
    returns (AaveAddresses memory aaveAddresses)
  {
    address governance = IPoolFactory(IPoolLogic(poolAddress).factory()).governanceAddress();
    address aaveProtocolDataProvider = IGovernance(governance).nameToDestination("aaveProtocolDataProvider");
    address aaveLendingPool = IGovernance(governance).nameToDestination("aaveLendingPool");

    return
      AaveAddresses(
        aaveProtocolDataProvider,
        aaveLendingPool,
        IHasSupportedAsset(IPoolLogic(poolAddress).poolManagerLogic()).isSupportedAsset(aaveLendingPool)
      );
  }

  /// @notice Enable PoolPerformance
  function enable() external onlyOwner {
    enabled = true;
  }
}
