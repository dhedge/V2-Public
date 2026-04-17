// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {SafeMath} from "@openzeppelin/contracts/math/SafeMath.sol";
import {WithdrawalHelperLib} from "../../../utils/WithdrawalHelperLib.sol";
import {IHasGuardInfo} from "../../../interfaces/IHasGuardInfo.sol";
import {IHasAssetInfo} from "../../../interfaces/IHasAssetInfo.sol";
import {IDytmPeriphery} from "../../../interfaces/dytm/IDytmPeriphery.sol";
import {IDytmOffice} from "../../../interfaces/dytm/IDytmOffice.sol";
import {DytmParamStructs} from "../../../utils/dytm/DytmParamStructs.sol";
import {DytmFlatteningLib} from "../../../utils/dytm/DytmFlatteningLib.sol";
import {DytmHelperLib} from "../../../utils/dytm/DytmHelperLib.sol";
import {ISwapDataConsumingGuard} from "../../../interfaces/guards/ISwapDataConsumingGuard.sol";
import {IDytmOfficeContractGuard} from "../../../interfaces/dytm/IDytmOfficeContractGuard.sol";

/// @title DytmSwapDataCalculator
/// @notice Abstract contract for calculating swap data parameters for DYTM withdrawal
/// @dev Frontend calls `calculateSwapDataParams` via `callStatic` to get data for constructing `complexAsset.withdrawData`.
///      computes portion-based amounts from the pre-split state.
abstract contract DytmSwapDataCalculator {
  using SafeMath for uint256;

  uint256 public constant BPS_DENOMINATOR = 10_000;

  uint256 public immutable mismatchDeltaNumerator;

  address public immutable pendleStaticRouter;

  address public immutable dytmOffice;

  address public immutable poolFactory;

  address public immutable dytmPeriphery;

  address public immutable accountSplitterAndMerger;

  address public immutable dytmWithdrawProcessor;

  /// @dev Ensures the function can only be called via eth_call (simulation), not in a real transaction
  modifier cannotExecute() {
    // solhint-disable-next-line avoid-tx-origin
    require(tx.origin == address(0), "only simulated call");
    _;
  }

  constructor(
    uint256 _mismatchDeltaNumerator,
    address _pendleStaticRouter,
    address _dytmOffice,
    address _poolFactory,
    address _dytmPeriphery,
    address _accountSplitterAndMerger,
    address _dytmWithdrawProcessor
  ) {
    require(_mismatchDeltaNumerator < BPS_DENOMINATOR, "invalid mismatch delta numerator");
    mismatchDeltaNumerator = _mismatchDeltaNumerator;
    pendleStaticRouter = _pendleStaticRouter;
    dytmOffice = _dytmOffice;
    poolFactory = _poolFactory;
    dytmPeriphery = _dytmPeriphery;
    accountSplitterAndMerger = _accountSplitterAndMerger;
    dytmWithdrawProcessor = _dytmWithdrawProcessor;
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Public functions
  // ──────────────────────────────────────────────────────────────────────────

  /// @notice Calculates the swap data parameters for frontend to construct offchain withdrawData
  /// @dev State mutating call — should be called using `callStatic` to avoid state changes
  /// @param _pool The pool logic address
  /// @param _poolTokenAmount The amount of pool tokens to be withdrawn
  /// @param _slippageTolerance Slippage tolerance in basis points
  /// @return params The swap data parameters
  function calculateSwapDataParams(
    address _pool,
    uint256 _poolTokenAmount,
    uint256 _slippageTolerance
  ) public virtual cannotExecute returns (ISwapDataConsumingGuard.SwapDataParams memory params) {
    require(_slippageTolerance <= BPS_DENOMINATOR, "invalid slippage tolerance");

    // Step 1: Pool-level portion calculation
    (uint256 portion, ) = WithdrawalHelperLib.calculateWithdrawalPortion(_pool, _poolTokenAmount);

    // Step 2: Get withdrawable positions and process
    uint256[] memory marketIds = _useContractGuard().getOwnedTokenIds(_pool);

    uint256 netValueD18;
    (params.srcData, params.dstData, netValueD18) = _processPositions(
      marketIds,
      _pool,
      dytmPeriphery,
      poolFactory,
      portion
    );

    // Step 3: Filter and convert based on debt status
    // - No debt: convert PTs to underlying
    // - Has debt + has non-debt collateral: filter out debt asset (including PTs whose underlying
    //   is the debt asset), calculate minDestAmount (Aave pattern), convert remaining PTs to underlying
    // - Has debt + all collateral is debt asset: srcData becomes empty after filtering, no swap needed
    if (params.dstData.asset != address(0)) {
      params = _filterSrcDataAndCalculateMinDst(params, poolFactory, _slippageTolerance, netValueD18);
    } else {
      DytmFlatteningLib.convertPTsToUnderlying(params.srcData, poolFactory, pendleStaticRouter);
    }

    // Step 4: Lower srcData amounts by 0.01% for management fee timing mismatch
    for (uint256 i; i < params.srcData.length; ++i) {
      params.srcData[i].amount = params.srcData[i].amount.mul(BPS_DENOMINATOR.sub(1)).div(BPS_DENOMINATOR);
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Internal helpers (shared with DytmOfficeAssetGuard)
  // ──────────────────────────────────────────────────────────────────────────

  /// @dev Get the DYTM Office contract guard
  function _useContractGuard() internal view returns (IDytmOfficeContractGuard) {
    return IDytmOfficeContractGuard(IHasGuardInfo(poolFactory).getContractGuard(dytmOffice));
  }

  /// @dev Check if a market position is healthy and has collateral
  function _isPositionWithdrawable(
    address _pool,
    uint88 _marketId,
    address _dytmPeriphery
  ) internal view returns (bool isValid, DytmParamStructs.AccountPosition memory position) {
    position = IDytmPeriphery(_dytmPeriphery).getAccountPosition({
      account: DytmHelperLib.toUserAccount(_pool),
      market: _marketId
    });
    isValid = position.isHealthy && position.totalCollateralValueUSD > 0;
  }

  /// @dev Accrue interest for all reserves across all markets and count total collaterals
  function _accrueInterestAndCountCollaterals(
    uint256[] memory _marketIds,
    uint256 _account,
    address _dytmOffice
  ) internal returns (uint256 totalCollaterals) {
    for (uint256 i; i < _marketIds.length; ++i) {
      totalCollaterals = totalCollaterals.add(
        DytmHelperLib.accruePositionInterest(IDytmOffice(_dytmOffice), _account, uint88(_marketIds[i]))
      );
    }
  }

  /// @dev Process all positions: classify debt and flatten collateral assets
  function _processPositions(
    uint256[] memory _marketIds,
    address _pool,
    address _dytmPeriphery,
    address _poolFactory,
    uint256 _portion
  )
    internal
    returns (
      ISwapDataConsumingGuard.AssetStructure[] memory srcData,
      ISwapDataConsumingGuard.AssetStructure memory dstData,
      uint256 netValueD18
    )
  {
    // Accrue interest for all reserves and count total collaterals for array sizing
    uint256 totalCollaterals = _accrueInterestAndCountCollaterals(
      _marketIds,
      DytmHelperLib.toUserAccount(_pool),
      dytmOffice
    );

    ISwapDataConsumingGuard.AssetStructure[] memory assets = new ISwapDataConsumingGuard.AssetStructure[](
      totalCollaterals * IHasAssetInfo(_poolFactory).getMaximumSupportedAssetCount()
    );
    uint256 count;

    // Process each position: query fresh data (interest already accrued) and flatten
    for (uint256 i; i < _marketIds.length; ++i) {
      (bool isValid, DytmParamStructs.AccountPosition memory position) = _isPositionWithdrawable(
        _pool,
        uint88(_marketIds[i]),
        _dytmPeriphery
      );
      if (!isValid) continue;

      dstData.asset = DytmFlatteningLib.trackDebtAsset(dstData.asset, position.debt);
      count = DytmFlatteningLib.flattenCollaterals(position.collaterals, _poolFactory, _portion, assets, count);
      // Net position value = collateral - debt, scaled by portion to match portioned srcData amounts
      netValueD18 = netValueD18.add(
        position.totalCollateralValueUSD.sub(position.debt.debtValueUSD).mul(_portion).div(1e18)
      );
    }

    // Deduplicate and sum amounts
    srcData = DytmFlatteningLib.deduplicateAssets(assets, count);
  }

  /// @dev Filter debt asset from srcData and calculate minDestAmount (Aave pattern)
  /// Delegates to DytmFlatteningLib.filterSrcDataAndCalculateMinDst
  function _filterSrcDataAndCalculateMinDst(
    ISwapDataConsumingGuard.SwapDataParams memory _params,
    address _poolFactory,
    uint256 _slippageTolerance,
    uint256 _netValueD18
  ) internal view returns (ISwapDataConsumingGuard.SwapDataParams memory) {
    (_params.srcData, _params.dstData.amount) = DytmFlatteningLib.filterSrcDataAndCalculateMinDst(
      _params.srcData,
      _params.dstData.asset,
      _poolFactory,
      _slippageTolerance,
      BPS_DENOMINATOR,
      pendleStaticRouter,
      _netValueD18
    );
    return _params;
  }
}
