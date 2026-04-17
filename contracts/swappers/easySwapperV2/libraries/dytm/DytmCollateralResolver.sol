// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {SafeMath} from "@openzeppelin/contracts/math/SafeMath.sol";
import {IPoolFactory} from "../../../../interfaces/IPoolFactory.sol";
import {IHasAssetInfo} from "../../../../interfaces/IHasAssetInfo.sol";
import {DytmParamStructs} from "../../../../utils/dytm/DytmParamStructs.sol";
import {DytmFlatteningLib} from "../../../../utils/dytm/DytmFlatteningLib.sol";
import {ISwapDataConsumingGuard} from "../../../../interfaces/guards/ISwapDataConsumingGuard.sol";

/// @title DytmCollateralResolver
/// @notice Abstract contract for resolving DYTM collaterals into flattened asset lists with amounts
/// @dev Provides functions to predict the deterministic token list and amounts resulting from unwinding DYTM positions.
///      dHEDGE vault collateral tokens are "flattened" to their underlying ERC20s with portion-based amounts.
abstract contract DytmCollateralResolver {
  using SafeMath for uint256;

  address public immutable dHedgePoolFactory;

  /// @dev Config values queried from asset guard and contract guard at runtime
  struct ResolverConfig {
    address dytmPeriphery;
    uint256 mismatchDeltaNumerator;
    uint256 bpsDenominator; // shared denominator for mismatch delta and slippage tolerance calculations
    address pendleStaticRouter;
  }

  /// @dev Accumulator for collecting collateral addresses and amounts across positions
  struct CollateralAccumulator {
    address[] allDhedgeTokens;
    address[] allPTs;
    ISwapDataConsumingGuard.AssetStructure[] allFlattenedAssets;
    uint256 dhedgeCount;
    uint256 ptCount;
    uint256 flattenedCount;
    address debtAsset;
  }

  constructor(address _dHedgePoolFactory) {
    dHedgePoolFactory = _dHedgePoolFactory;
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Public functions
  // ──────────────────────────────────────────────────────────────────────────

  /// @notice Get processed collateral info for pre-queried positions
  /// @dev Returns dhedgeTokens for processor steps, and swapDataParams for validation.
  ///   swapDataParams.srcData = flattened assets with debt asset filtered out (if has-debt)
  ///   swapDataParams.dstData = {debtAsset, minDstAmount} (or empty if no debt)
  /// @param _positions Pre-queried account positions
  /// @param _maxCollaterals Total collateral count across all positions (for array pre-allocation)
  /// @param _slippageTolerance Slippage tolerance in basis points for minDstAmount calculation
  /// @param _config Resolver config queried from guards
  /// @param _netValueD18 Net position value in USD (18 decimals) for leverage-based slippage scaling
  /// @return dhedgeTokens Collateral assets that are dHEDGE vault tokens
  /// @return swapDataParams Swap data with srcData (flattened, debt-filtered) and dstData (debt asset + minDstAmount)
  function resolveCollateralSwapData(
    DytmParamStructs.AccountPosition[] memory _positions,
    uint256 _maxCollaterals,
    uint256 _slippageTolerance,
    ResolverConfig memory _config,
    uint256 _netValueD18
  )
    internal
    returns (
      address[] memory dhedgeTokens,
      ISwapDataConsumingGuard.SwapDataParams memory swapDataParams,
      address[] memory ptAddresses
    )
  {
    CollateralAccumulator memory acc = _initAccumulator(_maxCollaterals);

    for (uint256 i; i < _positions.length; ++i) {
      _processPosition(_positions[i], acc);
    }

    // Collect PT addresses from flattened assets for later unrolling
    for (uint256 k; k < acc.flattenedCount; ++k) {
      if (IHasAssetInfo(dHedgePoolFactory).getAssetType(acc.allFlattenedAssets[k].asset) == 37) {
        acc.allPTs[acc.ptCount++] = acc.allFlattenedAssets[k].asset;
      }
    }

    // Single position: dhedgeTokens are already unique (one market),
    // only flattenedAssets needs dedup (dHEDGE underlyings may overlap with direct collaterals)
    if (_positions.length == 1) {
      DytmFlatteningLib.trimAddressArray(acc.allDhedgeTokens, acc.dhedgeCount);
      dhedgeTokens = acc.allDhedgeTokens;
    } else {
      dhedgeTokens = DytmFlatteningLib.deduplicateAddresses(acc.allDhedgeTokens, acc.dhedgeCount);
    }

    ptAddresses = DytmFlatteningLib.deduplicateAddresses(acc.allPTs, acc.ptCount);

    ISwapDataConsumingGuard.AssetStructure[] memory flattenedAssets = DytmFlatteningLib.deduplicateAssets(
      acc.allFlattenedAssets,
      acc.flattenedCount
    );

    // Note: PT conversion below may produce duplicate underlying entries (e.g. two PTs converting to the same underlying).
    // This is functionally fine — duplicate entries are handled correctly by downstream consumers.
    if (acc.debtAsset != address(0)) {
      (swapDataParams.srcData, swapDataParams.dstData.amount) = DytmFlatteningLib.filterSrcDataAndCalculateMinDst(
        flattenedAssets,
        acc.debtAsset,
        dHedgePoolFactory,
        _slippageTolerance,
        _config.bpsDenominator,
        _config.pendleStaticRouter,
        _netValueD18
      );
      swapDataParams.dstData.asset = acc.debtAsset;
    } else {
      DytmFlatteningLib.convertPTsToUnderlying(flattenedAssets, dHedgePoolFactory, _config.pendleStaticRouter);
      swapDataParams.srcData = flattenedAssets;
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Internal helpers
  // ──────────────────────────────────────────────────────────────────────────

  /// @dev Initialize the accumulator with properly sized arrays
  /// @param _maxCollaterals Total collateral count across all positions (for array pre-allocation)
  function _initAccumulator(uint256 _maxCollaterals) internal view returns (CollateralAccumulator memory acc) {
    uint256 maxFlattenedAssets = _maxCollaterals.mul(IHasAssetInfo(dHedgePoolFactory).getMaximumSupportedAssetCount());
    acc.allDhedgeTokens = new address[](_maxCollaterals);
    acc.allPTs = new address[](maxFlattenedAssets);
    acc.allFlattenedAssets = new ISwapDataConsumingGuard.AssetStructure[](maxFlattenedAssets);
  }

  /// @dev Process a single position: categorize collaterals, collect flattened assets, and track debt
  function _processPosition(
    DytmParamStructs.AccountPosition memory _position,
    CollateralAccumulator memory _acc
  ) internal {
    _acc.debtAsset = DytmFlatteningLib.trackDebtAsset(_acc.debtAsset, _position.debt);

    // Collect dHEDGE vault tokens for later withdrawal
    for (uint256 j; j < _position.collaterals.length; ++j) {
      address asset = _position.collaterals[j].asset;
      if (IPoolFactory(dHedgePoolFactory).isPool(asset)) {
        _acc.allDhedgeTokens[_acc.dhedgeCount++] = asset;
      }
    }

    // Flatten collaterals: non-dHEDGE kept as-is, dHEDGE resolved to underlyings
    // portion=0 → raw amounts (post-split, actual balances)
    _acc.flattenedCount = DytmFlatteningLib.flattenCollaterals(
      _position.collaterals,
      dHedgePoolFactory,
      0,
      _acc.allFlattenedAssets,
      _acc.flattenedCount
    );
  }
}
