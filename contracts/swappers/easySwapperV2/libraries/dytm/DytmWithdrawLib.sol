// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {SafeMath} from "@openzeppelin/contracts/math/SafeMath.sol";

import {IPoolLogic} from "../../../../interfaces/IPoolLogic.sol";
import {IHasGuardInfo} from "../../../../interfaces/IHasGuardInfo.sol";
import {IHasAssetInfo} from "../../../../interfaces/IHasAssetInfo.sol";
import {IERC20} from "../../../../interfaces/IERC20.sol";
import {IERC20Extended} from "../../../../interfaces/IERC20Extended.sol";
import {IDytmOffice} from "../../../../interfaces/dytm/IDytmOffice.sol";
import {IDytmPeriphery} from "../../../../interfaces/dytm/IDytmPeriphery.sol";
import {IDytmWithdrawProcessor} from "../../../../interfaces/dytm/IDytmWithdrawProcessor.sol";
import {IEasySwapperV2} from "../../interfaces/IEasySwapperV2.sol";
import {DytmParamStructs} from "../../../../utils/dytm/DytmParamStructs.sol";
import {DytmSplitTokenIdTracker} from "../../../../guards/assetGuards/dytm/DytmSplitTokenIdTracker.sol";
import {DytmOfficeAssetGuard} from "../../../../guards/assetGuards/dytm/DytmOfficeAssetGuard.sol";

/// @title DytmWithdrawLib
/// @notice Dispatcher invoked from `WithdrawalVault._unrollAssets` for the DYTM branch. Reads
///         the split positions populated during `withdrawProcessing`, transfers them to the
///         `DytmWithdrawProcessor`, and forwards the user's `UnwindPlan` to it.
library DytmWithdrawLib {
  using SafeMath for uint256;

  uint256 internal constant MAX_SLIPPAGE_TOLERANCE_BPS = 200; // 2% protocol-side cap
  uint256 internal constant BPS_DENOMINATOR = 10_000;
  /// @dev Absolute cap (USD, 1e18) on the dust remnant a split account may be left holding
  ///      when a sub-$1 GM leg can't be swapped via Ondo attestation. Bounds how much value
  ///      a plan can orphan back into the pool as an untracked isolated account.
  uint256 internal constant MAX_REMNANT_VALUE_USD = 3e18; // $3

  /// @notice One step in the unwind plan. Same shape as `IAssetGuard.MultiTransaction`.
  struct Action {
    address to;
    bytes data;
  }

  /// @notice User's withdrawal plan, encoded into `IPoolLogic.ComplexAsset.withdrawData`.
  struct UnwindPlan {
    Action[] actions;
    address outputAsset;
    uint256 minOutputAmount;
  }

  /// @notice Process DYTM position unwinding during EasySwapper withdrawal
  /// @param _dytmOffice DYTM Office address (asset type 106)
  /// @param _complexAsset Complex asset entry for the DYTM Office (positionally aligned with pool's supportedAssets upstream)
  /// @param _creator EasySwapperV2 address
  /// @param _dHedgeVault Pool the withdrawal is unrolling — used to constrain `outputAsset` to a pool-supported token
  /// @return tokensToTrack Tokens expected in vault after processing
  function processDytmPosition(
    address _dytmOffice,
    IPoolLogic.ComplexAsset memory _complexAsset,
    address _creator,
    address _dHedgeVault
  ) external returns (address[] memory tokensToTrack) {
    // 1. Read split positions — split accounts were transferred to this vault by the pool's withdrawProcessing.
    //    `address(this)` is the WithdrawalVault since this library runs in vault context.
    address assetGuard = _getAssetGuard(_dytmOffice, _creator);
    DytmSplitTokenIdTracker.SplitPosition[] memory splitPositions = DytmSplitTokenIdTracker(assetGuard)
      .getSplitPositions(address(this));
    if (splitPositions.length == 0) return tokensToTrack;

    require(_complexAsset.supportedAsset == _dytmOffice, "invalid asset");

    UnwindPlan memory plan = abi.decode(_complexAsset.withdrawData, (UnwindPlan));

    // 2. Transfer the split accounts to the processor and hand off the unwind.
    address processor = DytmOfficeAssetGuard(assetGuard).dytmWithdrawProcessor();

    // Lock the output asset to the processor's configured USDC: keeps the slippage cap below in
    // USD terms, prevents non-DEX-tradeable outputs (PT, dHEDGE pool tokens) from being handed
    // to the user, and removes the GM-output edge case that would denominate the cap in mint units.
    require(plan.outputAsset == IDytmWithdrawProcessor(processor).usdc(), "outputAsset must be USDC");

    // Protocol-side cap on slippage tolerance — caller can set tighter, never looser.
    require(_complexAsset.slippageTolerance <= MAX_SLIPPAGE_TOLERANCE_BPS, "slippage > 2%");

    // Snapshot `outputAsset` and the split positions' USD value before the unwind runs.
    address dytmPeriphery = DytmOfficeAssetGuard(assetGuard).dytmPeriphery();
    uint256 balanceBefore = IERC20(plan.outputAsset).balanceOf(address(this));
    uint256 expectedValueUSD = _sumSplitPositionsValueUSD(splitPositions, dytmPeriphery);

    for (uint256 i; i < splitPositions.length; ++i) {
      IDytmOffice(_dytmOffice).transfer(processor, splitPositions[i].tokenId, 1);
    }

    IDytmWithdrawProcessor(processor).process(
      IDytmWithdrawProcessor.UnwindPlanRequest({
        dytmOffice: _dytmOffice,
        pool: _dHedgeVault,
        splitPositions: splitPositions,
        actions: plan.actions,
        outputAsset: plan.outputAsset
      })
    );

    // A sub-$1 GM leg can't be swapped via Ondo attestation, so the processor may hand a dust
    // remnant back to the pool instead of fully draining a split account. Bound that remnant's
    // gross collateral; the depositor's forfeit of it is already covered by the slippage check.
    require(
      _sumSplitPositionsCollateralUSD(splitPositions, dytmPeriphery) <= MAX_REMNANT_VALUE_USD,
      "remnant too large"
    );

    uint256 received = IERC20(plan.outputAsset).balanceOf(address(this)).sub(balanceBefore);
    uint256 expectedOutput = _usdToOutputAmount(expectedValueUSD, plan.outputAsset, _dHedgeVault);
    require(
      received >= plan.minOutputAmount &&
        received.mul(BPS_DENOMINATOR) >= expectedOutput.mul(BPS_DENOMINATOR.sub(_complexAsset.slippageTolerance)),
      "high slippage"
    );

    tokensToTrack = new address[](1);
    tokensToTrack[0] = plan.outputAsset;
  }

  function _getAssetGuard(address _dytmOffice, address _creator) private view returns (address) {
    address poolFactory = IEasySwapperV2(_creator).dHedgePoolFactory();
    return IHasGuardInfo(poolFactory).getAssetGuard(_dytmOffice);
  }

  /// @dev Sum the net USD value (collateral − debt) of every split position the unwind owns,
  ///      using DYTM Periphery as the source of truth for position valuation.
  function _sumSplitPositionsValueUSD(
    DytmSplitTokenIdTracker.SplitPosition[] memory _splitPositions,
    address _dytmPeriphery
  ) private view returns (uint256 totalUSD) {
    for (uint256 i; i < _splitPositions.length; ++i) {
      DytmParamStructs.AccountPosition memory pos = IDytmPeriphery(_dytmPeriphery).getAccountPosition(
        _splitPositions[i].tokenId,
        _splitPositions[i].marketId
      );
      if (pos.totalCollateralValueUSD > pos.debt.debtValueUSD) {
        totalUSD = totalUSD.add(pos.totalCollateralValueUSD.sub(pos.debt.debtValueUSD));
      }
    }
  }

  /// @dev Sum the gross collateral USD of every split position. Called after the unwind to bound
  ///      the sub-$1 GM dust remnant the processor may leave behind; drained accounts add zero.
  function _sumSplitPositionsCollateralUSD(
    DytmSplitTokenIdTracker.SplitPosition[] memory _splitPositions,
    address _dytmPeriphery
  ) private view returns (uint256 totalUSD) {
    for (uint256 i; i < _splitPositions.length; ++i) {
      DytmParamStructs.AccountPosition memory pos = IDytmPeriphery(_dytmPeriphery).getAccountPosition(
        _splitPositions[i].tokenId,
        _splitPositions[i].marketId
      );
      totalUSD = totalUSD.add(pos.totalCollateralValueUSD);
    }
  }

  /// @dev Convert a USD value (1e18-scaled) to `_outputAsset` units. Only enforces the
  ///      staleness bound when the asset has a configured `maxPriceAge` (0 = no freshness
  ///      check, same convention as `PoolManagerLogic.totalFundValueWithMaxAge`).
  function _usdToOutputAmount(
    uint256 _usdValue,
    address _outputAsset,
    address _dHedgeVault
  ) private view returns (uint256) {
    address factory = IPoolLogic(_dHedgeVault).factory();
    (uint256 priceUSD, uint256 updatedAt, uint256 maxPriceAge) = IHasAssetInfo(factory).getAssetPriceWithTime(
      _outputAsset
    );
    if (maxPriceAge > 0) {
      require(block.timestamp.sub(updatedAt) <= maxPriceAge, "stale outputAsset price");
    }
    uint256 outputDecimals = IERC20Extended(_outputAsset).decimals();
    return _usdValue.mul(10 ** outputDecimals).div(priceUSD);
  }
}
