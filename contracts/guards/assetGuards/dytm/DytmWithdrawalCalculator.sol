// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {SafeMath} from "@openzeppelin/contracts/math/SafeMath.sol";
import {WithdrawalHelperLib} from "../../../utils/WithdrawalHelperLib.sol";
import {IHasGuardInfo} from "../../../interfaces/IHasGuardInfo.sol";
import {IHasAssetInfo} from "../../../interfaces/IHasAssetInfo.sol";
import {IPoolFactory} from "../../../interfaces/IPoolFactory.sol";
import {IDytmPeriphery} from "../../../interfaces/dytm/IDytmPeriphery.sol";
import {IDytmOffice} from "../../../interfaces/dytm/IDytmOffice.sol";
import {DytmParamStructs} from "../../../utils/dytm/DytmParamStructs.sol";
import {DytmHelperLib} from "../../../utils/dytm/DytmHelperLib.sol";
import {IDytmWithdrawalCalculator} from "../../../interfaces/guards/IDytmWithdrawalCalculator.sol";
import {IDytmOfficeContractGuard} from "../../../interfaces/dytm/IDytmOfficeContractGuard.sol";
import {AutomationBase} from "../../../utils/chainlink/AutomationBase.sol";

/// @title DytmWithdrawalCalculator
/// @notice Abstract size-discovery calculator for DYTM withdrawal. Single frontend entrypoint:
///         `previewWithdrawal(pool, X)` returns a flat `AssetData[]` — one entry per
///         collateral and per debt slot across every withdrawable DYTM market. Each entry carries
///         the raw `(asset, amount)` plus asset classification (`assetType`, `isPool`, `isDebt`)
///         and the DYTM action identifiers (`marketId`, `accountId`, `tokenId` / `debtKey`,
///         `shares`) so the frontend can build both off-chain work (DEX / Pendle / Ondo) and
///         on-chain `WithdrawParams` / `RepayParams` calldata in a single round-trip.
/// @dev    No on-chain swap-data planning, no flattening — the dispatcher is a generic multicall
///         executor, and dHEDGE-vault collateral underlyings are resolved client-side via
///         `isPool == true`.
abstract contract DytmWithdrawalCalculator is IDytmWithdrawalCalculator, AutomationBase {
  using SafeMath for uint256;

  uint256 public constant BPS_DENOMINATOR = 10_000;

  /// @notice Max total net equity (USD, 1e18) in unhealthy markets a withdrawal may skip.
  ///         - Above it, withdrawals revert until a keeper liquidates.
  ///         - Same $3 dust budget as MAX_REMNANT_VALUE_USD in DytmWithdrawLib.
  uint256 public constant MAX_FORFEIT_VALUE_USD = 3e18; // $3

  /// @notice Preview-emission buffer in bps — shrinks collateral, inflates debt. NOT a validation tolerance like Aave/Ondo.
  uint256 public immutable mismatchDeltaNumerator;

  address public immutable dytmOffice;

  address public immutable poolFactory;

  address public immutable dytmPeriphery;

  address public immutable accountSplitterAndMerger;

  constructor(
    uint256 _mismatchDeltaNumerator,
    address _dytmOffice,
    address _poolFactory,
    address _dytmPeriphery,
    address _accountSplitterAndMerger
  ) {
    require(_mismatchDeltaNumerator < BPS_DENOMINATOR, "invalid mismatch delta numerator");
    mismatchDeltaNumerator = _mismatchDeltaNumerator;
    dytmOffice = _dytmOffice;
    poolFactory = _poolFactory;
    dytmPeriphery = _dytmPeriphery;
    accountSplitterAndMerger = _accountSplitterAndMerger;
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Public functions
  // ──────────────────────────────────────────────────────────────────────────

  /// @inheritdoc IDytmWithdrawalCalculator
  /// @dev Emits one `AssetData` per collateral and per non-zero debt across every withdrawable market.
  ///      - Skips unhealthy / zero-collateral markets and reverts when the skipped net equity exceeds
  ///        MAX_FORFEIT_VALUE_USD — mirrors the on-chain split path (`DytmOfficeAssetGuard.withdrawProcessing`),
  ///        so blocked withdrawals surface at preview time.
  ///      - `accountId` is the DYTM-allocated next split account, pre-shifted by 160 bits, incremented
  ///        by one `<< 160` step per emitted market (markets share an `accountId` across their entries).
  ///      - `accountId` is a sim-time prediction; concurrent DYTM splits shift it — retry on revert.
  function previewWithdrawal(
    address _pool,
    uint256 _poolTokenAmount
  ) public virtual override cannotExecute returns (DytmParamStructs.AssetData[] memory assetData) {
    (uint256 portion, ) = WithdrawalHelperLib.calculateWithdrawalPortion(_pool, _poolTokenAmount);
    uint256[] memory marketIds = _useContractGuard().getOwnedTokenIds(_pool);

    uint256 baseAccountId = (uint256(IDytmOffice(dytmOffice).getAccountCount()) + 1) << 160;
    uint256 totalCollaterals = _accrueInterestAndCountCollaterals(
      marketIds,
      DytmHelperLib.toUserAccount(_pool),
      dytmOffice
    );

    // Upper bound: every collateral slot + at most one debt slot per market.
    // Unhealthy / zero-collateral markets contribute zero entries; trimmed at the end.
    assetData = new DytmParamStructs.AssetData[](totalCollaterals.add(marketIds.length));

    uint256 count;
    uint256 marketIndex;
    uint256 skippedEquityUSD;
    for (uint256 i; i < marketIds.length; ++i) {
      uint256 prevCount = count;
      (count, skippedEquityUSD) = _processOneMarket(
        assetData,
        count,
        _pool,
        uint88(marketIds[i]),
        baseAccountId + (marketIndex << 160),
        portion,
        skippedEquityUSD
      );
      // `marketIndex` only advances for processed markets so that the next allocated `accountId`
      // matches what DYTM will actually allocate during the on-chain split.
      if (count > prevCount) marketIndex++;
    }

    // Trim `assetData` to the populated entries.
    assembly {
      mstore(assetData, count)
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Internal helpers (shared with DytmOfficeAssetGuard)
  // ──────────────────────────────────────────────────────────────────────────

  /// @dev Get the DYTM Office contract guard
  function _useContractGuard() internal view returns (IDytmOfficeContractGuard) {
    return IDytmOfficeContractGuard(IHasGuardInfo(poolFactory).getContractGuard(dytmOffice));
  }

  /// @dev Check whether a market position can be split for withdrawal (healthy + has collateral).
  ///      - Unhealthy markets can't be split (DYTM reverts), so callers skip them and the
  ///        withdrawer's share of their net equity is forfeited to remaining holders.
  ///      - To bound that loss, callers thread a running total of skipped net equity through
  ///        `_skippedEquityUSD`; reverts once it exceeds MAX_FORFEIT_VALUE_USD.
  ///      - Net equity is clamped at zero — same valuation as `DytmOfficeAssetGuard.getBalance`.
  ///      - Lives here so preview and the on-chain split path enforce the same bound.
  function _checkWithdrawableAndForfeitBound(
    address _pool,
    uint88 _marketId,
    uint256 _skippedEquityUSD
  )
    internal
    view
    returns (bool isWithdrawable, DytmParamStructs.AccountPosition memory position, uint256 skippedEquityUSD)
  {
    position = IDytmPeriphery(dytmPeriphery).getAccountPosition({
      account: DytmHelperLib.toUserAccount(_pool),
      market: _marketId
    });
    isWithdrawable = position.isHealthy && position.totalCollateralValueUSD > 0;
    skippedEquityUSD = _skippedEquityUSD;
    if (!isWithdrawable && position.totalCollateralValueUSD > position.debt.debtValueUSD) {
      skippedEquityUSD = skippedEquityUSD.add(position.totalCollateralValueUSD.sub(position.debt.debtValueUSD));
      require(skippedEquityUSD <= MAX_FORFEIT_VALUE_USD, "unhealthy position too large");
    }
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

  /// @dev Process a single market: check withdrawability, then emit collateral + debt entries.
  ///      - Returns the updated write offset (unchanged if the market was skipped) and the
  ///        running skipped-equity total.
  function _processOneMarket(
    DytmParamStructs.AssetData[] memory _assetData,
    uint256 _count,
    address _pool,
    uint88 _marketId,
    uint256 _accountId,
    uint256 _portion,
    uint256 _skippedEquityUSD
  ) internal view returns (uint256 count, uint256 skippedEquityUSD) {
    bool isWithdrawable;
    DytmParamStructs.AccountPosition memory pos;
    (isWithdrawable, pos, skippedEquityUSD) = _checkWithdrawableAndForfeitBound(_pool, _marketId, _skippedEquityUSD);
    if (!isWithdrawable) return (_count, skippedEquityUSD);
    count = _emitMarketEntries(_assetData, _count, pos, _marketId, _accountId, _portion);
  }

  /// @dev Write one `AssetData` per collateral and one for the debt (if non-zero) into `_assetData`
  ///      starting at offset `_count`. Returns the updated write offset.
  function _emitMarketEntries(
    DytmParamStructs.AssetData[] memory _assetData,
    uint256 _count,
    DytmParamStructs.AccountPosition memory _pos,
    uint88 _marketId,
    uint256 _accountId,
    uint256 _portion
  ) internal view returns (uint256 count) {
    count = _count;
    // Buffer collateral DOWN (MF dilution) and debt UP (interest accrual) for sim→exec drift; excess swap output returns to vault via `uint256.max` repay.
    uint256 collateralBufferedPortion = _portion.mul(BPS_DENOMINATOR.sub(mismatchDeltaNumerator)).div(BPS_DENOMINATOR);
    uint256 debtBufferedPortion = _portion.mul(BPS_DENOMINATOR.add(mismatchDeltaNumerator)).div(BPS_DENOMINATOR);
    for (uint256 j; j < _pos.collaterals.length; ++j) {
      DytmParamStructs.CollateralInfo memory col = _pos.collaterals[j];
      _assetData[count++] = DytmParamStructs.AssetData({
        asset: col.asset,
        amount: col.assets.mul(collateralBufferedPortion).div(1e18),
        assetType: IHasAssetInfo(poolFactory).getAssetType(col.asset),
        isPool: IPoolFactory(poolFactory).isPool(col.asset),
        isDebt: false,
        marketId: _marketId,
        accountId: _accountId,
        tokenId: col.tokenId,
        debtKey: 0,
        shares: col.shares.mul(collateralBufferedPortion).div(1e18)
      });
    }
    if (_pos.debt.debtAssets > 0) {
      _assetData[count++] = DytmParamStructs.AssetData({
        asset: _pos.debt.debtAsset,
        amount: _pos.debt.debtAssets.mul(debtBufferedPortion).div(1e18),
        assetType: IHasAssetInfo(poolFactory).getAssetType(_pos.debt.debtAsset),
        isPool: IPoolFactory(poolFactory).isPool(_pos.debt.debtAsset),
        isDebt: true,
        marketId: _marketId,
        accountId: _accountId,
        tokenId: 0,
        debtKey: _pos.debt.debtKey,
        shares: _pos.debt.debtShares.mul(debtBufferedPortion).div(1e18)
      });
    }
  }
}
