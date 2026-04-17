// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {SafeMath} from "@openzeppelin/contracts/math/SafeMath.sol";
import {IPoolFactory} from "../../interfaces/IPoolFactory.sol";
import {IPoolManagerLogic} from "../../interfaces/IPoolManagerLogic.sol";
import {WithdrawalHelperLib} from "../WithdrawalHelperLib.sol";
import {IHasSupportedAsset} from "../../interfaces/IHasSupportedAsset.sol";
import {IHasAssetInfo} from "../../interfaces/IHasAssetInfo.sol";
import {IERC20Extended} from "../../interfaces/IERC20Extended.sol";
import {DytmParamStructs} from "./DytmParamStructs.sol";
import {ISwapDataConsumingGuard} from "../../interfaces/guards/ISwapDataConsumingGuard.sol";
import {PendlePTHandlerLib} from "../pendle/PendlePTHandlerLib.sol";

/// @title DytmFlatteningLib
/// @notice Shared library for resolving dHEDGE vault collaterals into underlying ERC20s and deduplication
/// @dev Used by both DytmCollateralResolver (runtime withdrawal) and DytmSwapDataCalculator (frontend callStatic)
library DytmFlatteningLib {
  using SafeMath for uint256;

  /// @dev Track debt asset from a position's debt info, requiring uniform debt asset across positions
  /// @param _currentDebtAsset The currently tracked debt asset (address(0) if none seen yet)
  /// @param _debt The debt info from the position
  /// @return debtAsset The updated debt asset address
  function trackDebtAsset(
    address _currentDebtAsset,
    DytmParamStructs.DebtInfo memory _debt
  ) internal pure returns (address debtAsset) {
    debtAsset = _currentDebtAsset;
    if (_debt.debtAssets > 0) {
      if (debtAsset == address(0)) {
        debtAsset = _debt.debtAsset;
      } else {
        require(debtAsset == _debt.debtAsset, "mixed debt assets not supported");
      }
    }
  }

  /// @dev Flatten collateral assets into a pre-allocated output array at a given offset.
  ///   Non-dHEDGE collaterals are kept as AssetStructure entries.
  ///   dHEDGE vault collaterals are resolved into their underlying ERC20s via getDhedgeUnderlyingAssets.
  ///
  ///   Portion handling:
  ///   - _portion == 0: Use raw collateral amounts directly (runtime withdrawal, post-split)
  ///   - _portion > 0:  Apply portion multiplier `amount * _portion / 1e18` (frontend callStatic, pre-split).
  ///                    Zero-amount results are skipped (Sherlock: prevents dust from portion rounding).
  ///
  /// @param _collaterals The collateral info array from a DYTM position
  /// @param _poolFactory The dHEDGE pool factory address (for isPool check and vault resolution)
  /// @param _portion Portion multiplier (1e18 precision). Pass 0 to use raw amounts
  /// @param _output Pre-allocated output array to append into
  /// @param _count Current write offset in the output array
  /// @return count Updated write offset after appending flattened assets
  function flattenCollaterals(
    DytmParamStructs.CollateralInfo[] memory _collaterals,
    address _poolFactory,
    uint256 _portion,
    ISwapDataConsumingGuard.AssetStructure[] memory _output,
    uint256 _count
  ) internal returns (uint256 count) {
    count = _count;

    for (uint256 j; j < _collaterals.length; ++j) {
      address asset = _collaterals[j].asset;
      uint256 amount = _portion > 0 ? _collaterals[j].assets.mul(_portion).div(1e18) : _collaterals[j].assets;
      if (amount == 0) continue;
      if (IPoolFactory(_poolFactory).isPool(asset)) {
        // dHEDGE vault: resolve to underlying assets
        ISwapDataConsumingGuard.AssetStructure[] memory underlyings = getDhedgeUnderlyingAssets(
          asset,
          amount,
          _poolFactory
        );
        for (uint256 k; k < underlyings.length; ++k) {
          _output[count] = underlyings[k];
          ++count;
        }
      } else {
        // Direct collateral
        _output[count] = ISwapDataConsumingGuard.AssetStructure({asset: asset, amount: amount});
        ++count;
      }
    }
  }

  /// @dev Resolve a dHEDGE vault token into underlying ERC20s with portion-based amounts
  /// @param _dhedgeToken The dHEDGE vault token address
  /// @param _vaultTokenAmount The amount of vault tokens
  /// @param _poolFactory The dHEDGE pool factory address
  /// @return underlyings Array of underlying asset + amount pairs
  function getDhedgeUnderlyingAssets(
    address _dhedgeToken,
    uint256 _vaultTokenAmount,
    address _poolFactory
  ) internal returns (ISwapDataConsumingGuard.AssetStructure[] memory underlyings) {
    (uint256 vaultPortion, address poolManagerLogic) = WithdrawalHelperLib.calculateWithdrawalPortion(
      _dhedgeToken,
      _vaultTokenAmount
    );
    IHasSupportedAsset.Asset[] memory supportedAssets = IHasSupportedAsset(poolManagerLogic).getSupportedAssets();

    underlyings = new ISwapDataConsumingGuard.AssetStructure[](supportedAssets.length);
    uint256 count;

    for (uint256 i; i < supportedAssets.length; ++i) {
      address asset = supportedAssets[i].asset;
      uint256 totalBalance = IPoolManagerLogic(poolManagerLogic).assetBalance(asset);

      uint256 portionAmount = totalBalance.mul(vaultPortion).div(1e18);
      if (portionAmount == 0) continue;

      uint16 assetType = IHasAssetInfo(_poolFactory).getAssetType(asset);
      // 0 = Chainlink direct USD price feed (ERC20)
      // 4 = Lending Enabled Asset
      // 37 = Pendle Principal Token
      // 200 = Reward Asset
      require(
        assetType == 0 || assetType == 4 || assetType == 37 || assetType == 200,
        "invalid dhedge underlying type"
      );
      require(!IPoolFactory(_poolFactory).isPool(asset), "nested dhedge not supported");

      underlyings[count] = ISwapDataConsumingGuard.AssetStructure({asset: asset, amount: portionAmount});
      ++count;
    }

    trimAssetArray(underlyings, count);
  }

  /// @dev Deduplicate AssetStructure entries, summing amounts for duplicate addresses
  function deduplicateAssets(
    ISwapDataConsumingGuard.AssetStructure[] memory _input,
    uint256 _length
  ) internal pure returns (ISwapDataConsumingGuard.AssetStructure[] memory deduplicated) {
    deduplicated = new ISwapDataConsumingGuard.AssetStructure[](_length);
    uint256 uniqueCount;

    for (uint256 i; i < _length; ++i) {
      bool isDuplicate;
      for (uint256 j; j < uniqueCount; ++j) {
        if (deduplicated[j].asset == _input[i].asset) {
          deduplicated[j].amount = deduplicated[j].amount.add(_input[i].amount);
          isDuplicate = true;
          break;
        }
      }
      if (!isDuplicate) {
        deduplicated[uniqueCount] = _input[i];
        ++uniqueCount;
      }
    }

    trimAssetArray(deduplicated, uniqueCount);
  }

  /// @dev Deduplicate addresses preserving first-occurrence order
  function deduplicateAddresses(
    address[] memory _input,
    uint256 _length
  ) internal pure returns (address[] memory deduplicated) {
    deduplicated = new address[](_length);
    uint256 uniqueCount;

    for (uint256 i; i < _length; ++i) {
      bool isDuplicate;
      for (uint256 j; j < uniqueCount; ++j) {
        if (deduplicated[j] == _input[i]) {
          isDuplicate = true;
          break;
        }
      }
      if (!isDuplicate) {
        deduplicated[uniqueCount++] = _input[i];
      }
    }

    trimAddressArray(deduplicated, uniqueCount);
  }

  /// @dev Filter debt asset from srcData and calculate minDstAmount (Aave pattern)
  /// Resolves PT underlyings to detect debt asset matches (e.g. PT-USDC underlying is USDC),
  /// sums USD value of assets to swap (at PT price for PTs — more resilient against PT conversion variance),
  /// converts PTs to underlying token+amount, then converts total value to debt asset amount with slippage.
  /// Scales slippage tolerance based on leverage when swap value exceeds net position value.
  function filterSrcDataAndCalculateMinDst(
    ISwapDataConsumingGuard.AssetStructure[] memory _srcData,
    address _debtAsset,
    address _poolFactory,
    uint256 _slippageTolerance,
    uint256 _slippageToleranceDenominator,
    address _pendleStaticRouter,
    uint256 _netValueD18
  ) internal view returns (ISwapDataConsumingGuard.AssetStructure[] memory filteredSrcData, uint256 minDstAmount) {
    filteredSrcData = new ISwapDataConsumingGuard.AssetStructure[](_srcData.length);
    uint256 count;
    uint256 assetsToSwapValueD18;

    for (uint256 i; i < _srcData.length; ++i) {
      // Resolve effective asset: underlying for PTs, itself for non-PTs
      address effectiveAsset = _srcData[i].asset;
      if (IHasAssetInfo(_poolFactory).getAssetType(effectiveAsset) == 37) {
        (, effectiveAsset) = PendlePTHandlerLib.getPTAssociatedDataByFactory(effectiveAsset, _poolFactory);
      }

      // Filter out if effective asset is the debt asset (catches both direct and PT-underlying matches)
      if (effectiveAsset == _debtAsset) continue;

      // Sum value at current price (PT price for PTs — before conversion)
      assetsToSwapValueD18 = assetsToSwapValueD18.add(assetValueD18(_srcData[i], _poolFactory));

      // Convert PT to underlying in-place after value calculation (Aave pattern:
      // minDstAmount is based on PT value, not underlying value after conversion)
      if (effectiveAsset != _srcData[i].asset) {
        PendlePTHandlerLib.convertPendlePTToUnderlyingByFactory(_srcData[i], _poolFactory, _pendleStaticRouter);
      }

      // Copy once (already converted) to filtered array
      filteredSrcData[count] = _srcData[i];
      ++count;
    }
    trimAssetArray(filteredSrcData, count);

    // Scale slippage tolerance based on leverage.
    // Swap slippage is amplified on the net position: net_slippage = swap_slippage × (swapValue / netValue)
    // Rearranging: swap_tolerance = net_tolerance × (netValue / swapValue)
    // Only scale if swap value exceeds net value (i.e. leverage amplification exists for the swapped portion).
    // If netValue is 0 (debt == collateral), slippage tolerance becomes 0 (maximally strict).
    if (assetsToSwapValueD18 > _netValueD18) {
      _slippageTolerance = _slippageTolerance.mul(_netValueD18).div(assetsToSwapValueD18);
    }

    // Convert total USD value to debt asset denomination with slippage
    {
      uint256 dstAssetPriceD18 = IHasAssetInfo(_poolFactory).getAssetPrice(_debtAsset);
      uint256 dstAssetDecimals = 10 ** IERC20Extended(_debtAsset).decimals();
      minDstAmount = assetsToSwapValueD18
        .mul(dstAssetDecimals)
        .div(dstAssetPriceD18)
        .mul(_slippageToleranceDenominator.sub(_slippageTolerance))
        .div(_slippageToleranceDenominator);
    }
  }

  /// @dev Convert all Pendle PT entries in the array to their underlying token+amount
  function convertPTsToUnderlying(
    ISwapDataConsumingGuard.AssetStructure[] memory _assets,
    address _poolFactory,
    address _pendleStaticRouter
  ) internal view {
    for (uint256 i; i < _assets.length; ++i) {
      if (IHasAssetInfo(_poolFactory).getAssetType(_assets[i].asset) == 37) {
        PendlePTHandlerLib.convertPendlePTToUnderlyingByFactory(_assets[i], _poolFactory, _pendleStaticRouter);
      }
    }
  }

  /// @dev Sum USD value (18 decimals) of all assets in the array
  function sumAssetsValueD18(
    ISwapDataConsumingGuard.AssetStructure[] memory _assets,
    address _poolFactory
  ) internal view returns (uint256 totalValueD18) {
    for (uint256 i; i < _assets.length; ++i) {
      totalValueD18 = totalValueD18.add(assetValueD18(_assets[i], _poolFactory));
    }
  }

  /// @dev Calculate USD value (18 decimals) of an asset amount
  function assetValueD18(
    ISwapDataConsumingGuard.AssetStructure memory _asset,
    address _poolFactory
  ) internal view returns (uint256) {
    uint256 price = IHasAssetInfo(_poolFactory).getAssetPrice(_asset.asset);
    uint256 decimals = 10 ** IERC20Extended(_asset.asset).decimals();
    return _asset.amount.mul(price).div(decimals);
  }

  /// @dev Trim a memory AssetStructure array to the specified length using assembly
  function trimAssetArray(ISwapDataConsumingGuard.AssetStructure[] memory _array, uint256 _newLength) internal pure {
    assembly {
      mstore(_array, _newLength)
    }
  }

  /// @dev Trim a memory address array to the specified length using assembly
  function trimAddressArray(address[] memory _array, uint256 _newLength) internal pure {
    assembly {
      mstore(_array, _newLength)
    }
  }
}
