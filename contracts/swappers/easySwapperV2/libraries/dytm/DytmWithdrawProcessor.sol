// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {SafeMath} from "@openzeppelin/contracts/math/SafeMath.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IDytmDelegatee} from "../../../../interfaces/dytm/IDytmDelegatee.sol";
import {IDytmOffice} from "../../../../interfaces/dytm/IDytmOffice.sol";
import {IDytmPeriphery} from "../../../../interfaces/dytm/IDytmPeriphery.sol";
import {DytmOfficeAssetGuard} from "../../../../guards/assetGuards/dytm/DytmOfficeAssetGuard.sol";
import {IHasGuardInfo} from "../../../../interfaces/IHasGuardInfo.sol";
import {IPoolLogic} from "../../../../interfaces/IPoolLogic.sol";
import {IEasySwapperV2} from "../../interfaces/IEasySwapperV2.sol";
import {IERC20} from "../../../../interfaces/IERC20.sol";
import {SafeERC20} from "../../../../utils/SafeERC20.sol";
import {DytmParamStructs} from "../../../../utils/dytm/DytmParamStructs.sol";
import {DytmSplitTokenIdTracker} from "../../../../guards/assetGuards/dytm/DytmSplitTokenIdTracker.sol";
import {DytmCollateralResolver} from "./DytmCollateralResolver.sol";
import {DytmFlatteningLib} from "../../../../utils/dytm/DytmFlatteningLib.sol";
import {DytmHelperLib} from "../../../../utils/dytm/DytmHelperLib.sol";
import {ISwapDataConsumingGuard} from "../../../../interfaces/guards/ISwapDataConsumingGuard.sol";
import {ISwapper} from "../../../../interfaces/flatMoney/swapper/ISwapper.sol";
import {SwapperV2Helpers} from "../SwapperV2Helpers.sol";

/// @title DytmWithdrawProcessor
/// @notice Processor contract for unwinding DYTM positions during EasySwapperV2 withdrawal
/// @dev Called via IDytmOffice.delegationCall to withdraw collaterals and flatten dHEDGE vault tokens
contract DytmWithdrawProcessor is IDytmDelegatee, DytmCollateralResolver, Ownable {
  using SafeMath for uint256;
  using SafeERC20 for IERC20;

  address public immutable dytmOffice;
  address public immutable easySwapperV2;

  constructor(
    address _dytmOffice,
    address _dHedgePoolFactory,
    address _easySwapperV2
  ) DytmCollateralResolver(_dHedgePoolFactory) {
    dytmOffice = _dytmOffice;
    easySwapperV2 = _easySwapperV2;
  }

  /// @notice Allows the contract owner to recover any ERC20 tokens (e.g., dust) from this contract
  /// @param _token The ERC20 token to withdraw
  /// @param _amount The amount to withdraw
  function salvage(IERC20 _token, uint256 _amount) external onlyOwner {
    _token.safeTransfer(msg.sender, _amount);
  }

  /// @dev Bundled context for onDelegationCallback to avoid stack-too-deep
  struct CallbackContext {
    address vault;
    uint256 slippageTolerance;
    uint256 totalPositionValueD18;
  }

  // ──────────────────────────────────────────────────────────────────────────
  // onDelegationCallback
  // ──────────────────────────────────────────────────────────────────────────

  /// @notice Entry point called by IDytmOffice.delegationCall during withdrawal processing
  /// @param _callbackData Encoded (SplitPosition[], withdrawer, ComplexAsset)
  function onDelegationCallback(bytes calldata _callbackData) external override returns (bytes memory) {
    require(msg.sender == dytmOffice, "invalid caller");

    // Query config from guards
    ResolverConfig memory config = _queryConfig();

    CallbackContext memory ctx;
    ctx.vault = IDytmOffice(dytmOffice).callerContext();
    DytmSplitTokenIdTracker.SplitPosition[] memory splitPositions;
    ISwapDataConsumingGuard.ComplexAssetSwapData memory swapData;

    // Step 1: Decode callbackData and swap data
    {
      address withdrawer;
      IPoolLogic.ComplexAsset memory complexAsset;
      (splitPositions, withdrawer, complexAsset) = abi.decode(
        _callbackData,
        (DytmSplitTokenIdTracker.SplitPosition[], address, IPoolLogic.ComplexAsset)
      );
      require(complexAsset.supportedAsset == dytmOffice, "invalid asset");
      require(IEasySwapperV2(easySwapperV2).withdrawalContracts(withdrawer) == ctx.vault, "invalid vault");

      ctx.slippageTolerance = complexAsset.slippageTolerance;
      require(ctx.slippageTolerance <= config.bpsDenominator, "slippage tolerance too high");
      if (complexAsset.withdrawData.length > 0) {
        swapData = abi.decode(complexAsset.withdrawData, (ISwapDataConsumingGuard.ComplexAssetSwapData));
      }
    }

    // Step 2: Query positions
    DytmParamStructs.AccountPosition[] memory positions;
    uint256 maxCollaterals;
    {
      (positions, maxCollaterals, ctx.totalPositionValueD18) = _queryPositions(splitPositions, config.dytmPeriphery);
    }

    ISwapDataConsumingGuard.SwapDataParams memory swapDataParams;
    uint256 debtAssetBalanceBefore;

    // Step 3: Resolve collateral swap data
    {
      address[] memory dhedgeTokens;
      address[] memory ptAddresses;
      (dhedgeTokens, swapDataParams, ptAddresses) = resolveCollateralSwapData(
        positions,
        maxCollaterals,
        ctx.slippageTolerance,
        config,
        ctx.totalPositionValueD18
      );

      // Capture debt asset balance before any withdrawals (for balance-diff in debt case)
      if (swapDataParams.dstData.asset != address(0)) {
        debtAssetBalanceBefore = IERC20(swapDataParams.dstData.asset).balanceOf(address(this));
      }

      // Step 4: Withdraw collaterals, flatten dHEDGE vault tokens, and unroll PTs
      _withdrawAndFlattenCollaterals(splitPositions, positions, dhedgeTokens);
      _unrollPendlePTs(ptAddresses);
    }

    // Step 5: Settle based on debt and swap status
    // - No debt: transfer collateral to vault
    // - Has debt + needs swap (srcData not empty): swap collateral → debt asset, repay, transfer
    // - Has debt + no swap needed (srcData empty, all collateral is debt asset): repay, transfer
    uint256 minValueD18 = ctx.totalPositionValueD18.mul(config.bpsDenominator.sub(ctx.slippageTolerance)).div(
      config.bpsDenominator
    );
    if (swapDataParams.dstData.asset == address(0)) {
      _processNoDebtCase(swapDataParams.srcData, ctx.vault, config, minValueD18);
    } else if (swapDataParams.srcData.length > 0) {
      require(swapData.srcData.length > 0, "swap data required for debt");
      _processDebtCase(
        swapDataParams,
        swapData,
        splitPositions,
        positions,
        ctx.vault,
        config,
        debtAssetBalanceBefore,
        minValueD18
      );
    } else {
      // Has debt but all collateral is the debt asset — no swap needed, just repay and transfer
      _processDebtNoSwapCase(
        splitPositions,
        positions,
        swapDataParams.dstData.asset,
        ctx.vault,
        debtAssetBalanceBefore,
        minValueD18
      );
    }

    // Step 6: Derive tokens to track in vault after processing (debt asset if has-debt, all src assets if no-debt)
    return abi.encode(_deriveTokensToTrack(swapDataParams));
  }

  /// @dev Derive tokens to track in vault after processing
  function _deriveTokensToTrack(
    ISwapDataConsumingGuard.SwapDataParams memory _swapDataParams
  ) internal pure returns (address[] memory tokensToTrack) {
    if (_swapDataParams.dstData.asset != address(0)) {
      tokensToTrack = new address[](1);
      tokensToTrack[0] = _swapDataParams.dstData.asset;
    } else {
      tokensToTrack = new address[](_swapDataParams.srcData.length);
      for (uint256 i; i < _swapDataParams.srcData.length; ++i) {
        tokensToTrack[i] = _swapDataParams.srcData[i].asset;
      }
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Internal helpers
  // ──────────────────────────────────────────────────────────────────────────

  /// @dev Query config from asset guard
  function _queryConfig() internal view returns (ResolverConfig memory config) {
    DytmOfficeAssetGuard assetGuard = DytmOfficeAssetGuard(IHasGuardInfo(dHedgePoolFactory).getAssetGuard(dytmOffice));
    config.mismatchDeltaNumerator = assetGuard.mismatchDeltaNumerator();
    config.bpsDenominator = assetGuard.BPS_DENOMINATOR();
    config.pendleStaticRouter = assetGuard.pendleStaticRouter();
    config.dytmPeriphery = assetGuard.dytmPeriphery();
  }

  /// @dev Query all account positions for the given split positions
  /// @return positions The queried account positions
  /// @return maxCollaterals Total number of collateral entries across all positions (for array pre-allocation)
  /// @return totalPositionValueD18 Sum of net position values (collateral - debt) in USD (18 decimals)
  function _queryPositions(
    DytmSplitTokenIdTracker.SplitPosition[] memory _splitPositions,
    address _dytmPeriphery
  )
    internal
    returns (DytmParamStructs.AccountPosition[] memory positions, uint256 maxCollaterals, uint256 totalPositionValueD18)
  {
    positions = new DytmParamStructs.AccountPosition[](_splitPositions.length);
    for (uint256 i; i < _splitPositions.length; ++i) {
      // Accrue interest for all reserves before querying for fresh data
      DytmHelperLib.accruePositionInterest(
        IDytmOffice(dytmOffice),
        _splitPositions[i].tokenId,
        _splitPositions[i].marketId
      );

      positions[i] = IDytmPeriphery(_dytmPeriphery).getAccountPosition(
        _splitPositions[i].tokenId,
        _splitPositions[i].marketId
      );
      maxCollaterals = maxCollaterals.add(positions[i].collaterals.length);
      // Net position value = collateral - debt (for no-debt, debtValueUSD == 0)
      totalPositionValueD18 = totalPositionValueD18.add(
        positions[i].totalCollateralValueUSD.sub(positions[i].debt.debtValueUSD)
      );
    }
  }

  /// @dev Withdraw all collaterals for a single position from the DYTM office
  function _withdrawCollaterals(uint256 _tokenId, DytmParamStructs.AccountPosition memory _position) internal {
    for (uint256 j; j < _position.collaterals.length; ++j) {
      if (_position.collaterals[j].shares == 0) continue;
      IDytmOffice(dytmOffice).withdraw(
        DytmParamStructs.WithdrawParams({
          account: _tokenId,
          tokenId: _position.collaterals[j].tokenId,
          receiver: address(this),
          assets: 0,
          shares: _position.collaterals[j].shares,
          extraData: ""
        })
      );
    }
  }

  /// @dev Withdraw from dHEDGE vault tokens to flatten to underlying ERC20s
  function _withdrawDhedgeVaults(address[] memory _dhedgeTokens) internal {
    for (uint256 i; i < _dhedgeTokens.length; ++i) {
      uint256 balance = IERC20(_dhedgeTokens[i]).balanceOf(address(this));
      if (balance == 0) continue;
      IPoolLogic(_dhedgeTokens[i]).withdraw(balance);
    }
  }

  /// @dev Unroll Pendle PT tokens to their underlying tokens
  function _unrollPendlePTs(address[] memory _ptAddresses) internal {
    for (uint256 i; i < _ptAddresses.length; ++i) {
      SwapperV2Helpers.unrollPendlePTByFactory(dHedgePoolFactory, _ptAddresses[i]);
    }
  }

  /// @dev Withdraw all collaterals and flatten dHEDGE vault tokens to underlying ERC20s
  function _withdrawAndFlattenCollaterals(
    DytmSplitTokenIdTracker.SplitPosition[] memory _splitPositions,
    DytmParamStructs.AccountPosition[] memory _positions,
    address[] memory _dhedgeTokens
  ) internal {
    for (uint256 i; i < _splitPositions.length; ++i) {
      _withdrawCollaterals(_splitPositions[i].tokenId, _positions[i]);
    }
    _withdrawDhedgeVaults(_dhedgeTokens);
  }

  /// @dev Transfer all flattened asset balances to the withdrawal vault
  /// @notice Caps transfer to actual balance if predicted amount exceeds it (within mismatch tolerance)
  function _transferAssetAmountsToVault(
    ISwapDataConsumingGuard.AssetStructure[] memory _flattenedAssets,
    address _vault,
    ResolverConfig memory _config
  ) internal {
    for (uint256 i; i < _flattenedAssets.length; ++i) {
      uint256 amount = _flattenedAssets[i].amount;
      uint256 balance = IERC20(_flattenedAssets[i].asset).balanceOf(address(this));
      if (amount > balance) {
        require(
          amount.sub(balance) <= amount.mul(_config.mismatchDeltaNumerator).div(_config.bpsDenominator),
          "transfer amount mismatch"
        );
        _flattenedAssets[i].amount = balance;
      }
      IERC20(_flattenedAssets[i].asset).safeTransfer(_vault, _flattenedAssets[i].amount);
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // No-debt case
  // ──────────────────────────────────────────────────────────────────────────

  /// @dev Process the no-debt case: transfer flattened assets to vault with slippage check
  function _processNoDebtCase(
    ISwapDataConsumingGuard.AssetStructure[] memory _srcData,
    address _vault,
    ResolverConfig memory _config,
    uint256 _minValueD18
  ) internal {
    _transferAssetAmountsToVault(_srcData, _vault, _config);
    _checkWithdrawalSlippage(DytmFlatteningLib.sumAssetsValueD18(_srcData, dHedgePoolFactory), _minValueD18);
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Has-debt case
  // ──────────────────────────────────────────────────────────────────────────

  /// @dev Process the has-debt case: swap → debt asset, repay debts, transfer to vault
  /// @param _debtAssetBalanceBefore Debt asset balance captured before any withdrawals (for balance-diff)
  function _processDebtCase(
    ISwapDataConsumingGuard.SwapDataParams memory _swapDataParams,
    ISwapDataConsumingGuard.ComplexAssetSwapData memory _swapData,
    DytmSplitTokenIdTracker.SplitPosition[] memory _splitPositions,
    DytmParamStructs.AccountPosition[] memory _positions,
    address _vault,
    ResolverConfig memory _config,
    uint256 _debtAssetBalanceBefore,
    uint256 _minValueD18
  ) internal {
    // Validate offchain swap data against current state
    ISwapper.SrcTokenSwapDetails[] memory srcTokenSwapDetails = _validateSwapData(_swapDataParams, _swapData, _config);

    _swapCollateralsToDebtAsset(srcTokenSwapDetails, _swapData.destData);

    // Repay all position debts
    _repayDebts(_splitPositions, _positions);

    _settleDebtAssetAndCheckSlippage(_swapDataParams.dstData.asset, _debtAssetBalanceBefore, _vault, _minValueD18);
  }

  /// @dev Process the has-debt case when all collateral is the debt asset (no swap needed)
  function _processDebtNoSwapCase(
    DytmSplitTokenIdTracker.SplitPosition[] memory _splitPositions,
    DytmParamStructs.AccountPosition[] memory _positions,
    address _debtAsset,
    address _vault,
    uint256 _debtAssetBalanceBefore,
    uint256 _minValueD18
  ) internal {
    _repayDebts(_splitPositions, _positions);
    _settleDebtAssetAndCheckSlippage(_debtAsset, _debtAssetBalanceBefore, _vault, _minValueD18);
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Settlement and slippage helpers
  // ──────────────────────────────────────────────────────────────────────────

  /// @dev Transfer debt asset balance gain to vault and check withdrawal slippage
  function _settleDebtAssetAndCheckSlippage(
    address _debtAsset,
    uint256 _debtAssetBalanceBefore,
    address _vault,
    uint256 _minValueD18
  ) internal {
    uint256 debtAssetGained = IERC20(_debtAsset).balanceOf(address(this)).sub(_debtAssetBalanceBefore);
    if (debtAssetGained > 0) {
      IERC20(_debtAsset).safeTransfer(_vault, debtAssetGained);
    }
    _checkWithdrawalSlippage(
      DytmFlatteningLib.assetValueD18(
        ISwapDataConsumingGuard.AssetStructure({asset: _debtAsset, amount: debtAssetGained}),
        dHedgePoolFactory
      ),
      _minValueD18
    );
  }

  /// @dev Require received value meets minimum after slippage tolerance
  function _checkWithdrawalSlippage(uint256 _receivedValueD18, uint256 _minValueD18) internal pure {
    require(_receivedValueD18 >= _minValueD18, "high withdrawal slippage");
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Has-debt helpers
  // ──────────────────────────────────────────────────────────────────────────

  /// @dev Validate offchain swap data against current state params (Aave pattern)
  function _validateSwapData(
    ISwapDataConsumingGuard.SwapDataParams memory _currentStateParams,
    ISwapDataConsumingGuard.ComplexAssetSwapData memory _swapData,
    ResolverConfig memory _config
  ) internal pure returns (ISwapper.SrcTokenSwapDetails[] memory srcTokenSwapDetails) {
    srcTokenSwapDetails = abi.decode(_swapData.srcData, (ISwapper.SrcTokenSwapDetails[]));
    require(srcTokenSwapDetails.length == _currentStateParams.srcData.length, "swap data length mismatch");

    for (uint256 i; i < srcTokenSwapDetails.length; ++i) {
      _validateSrcToken(srcTokenSwapDetails[i], _currentStateParams.srcData[i], _config);
    }
    _validateDstToken(_swapData.destData, _currentStateParams.dstData, _config);
  }

  /// @dev Validate a single source token in swap data against current state
  function _validateSrcToken(
    ISwapper.SrcTokenSwapDetails memory _swapSrcData,
    ISwapDataConsumingGuard.AssetStructure memory _currentSrcData,
    ResolverConfig memory _config
  ) internal pure {
    require(address(_swapSrcData.token) == _currentSrcData.asset, "src asset mismatch");
    // Swap amount can't exceed available amount
    require(_swapSrcData.amount <= _currentSrcData.amount, "src amount too high");
    // Swap amount can't be too far below expected (within mismatch delta)
    require(
      _currentSrcData.amount.sub(_swapSrcData.amount) <=
        _currentSrcData.amount.mul(_config.mismatchDeltaNumerator).div(_config.bpsDenominator),
      "src amount mismatch"
    );
  }

  /// @dev Validate destination token in swap data against current state
  function _validateDstToken(
    ISwapper.DestData memory _swapDstData,
    ISwapDataConsumingGuard.AssetStructure memory _currentDstData,
    ResolverConfig memory _config
  ) internal pure {
    require(address(_swapDstData.destToken) == _currentDstData.asset, "dst asset mismatch");
    // minDestAmount must be within delta range of calculated amount
    uint256 delta = _currentDstData.amount.mul(_config.mismatchDeltaNumerator).div(_config.bpsDenominator);
    require(
      _swapDstData.minDestAmount <= _currentDstData.amount.add(delta) &&
        _swapDstData.minDestAmount >= _currentDstData.amount.sub(delta),
      "dst amount mismatch"
    );
  }

  /// @dev Swap non-debt collaterals to debt asset via the Swapper
  function _swapCollateralsToDebtAsset(
    ISwapper.SrcTokenSwapDetails[] memory _srcTokenSwapDetails,
    ISwapper.DestData memory _destData
  ) internal {
    if (_srcTokenSwapDetails.length == 0) return;

    ISwapper swapper = IEasySwapperV2(easySwapperV2).swapper();

    // Approve swapper for all src tokens
    for (uint256 i; i < _srcTokenSwapDetails.length; ++i) {
      IERC20(address(_srcTokenSwapDetails[i].token)).safeIncreaseAllowance(
        address(swapper),
        _srcTokenSwapDetails[i].amount
      );
    }

    // Build swap props and execute
    ISwapper.InOutData memory swapProps;
    ISwapper.SrcData[] memory srcData = new ISwapper.SrcData[](1);
    srcData[0].srcTokenSwapDetails = _srcTokenSwapDetails;
    srcData[0].transferMethodData.method = ISwapper.TransferMethod.ALLOWANCE;
    swapProps.srcData = srcData;
    swapProps.destData = _destData;

    swapper.swap(swapProps);
  }

  /// @dev Repay debt for all positions
  function _repayDebts(
    DytmSplitTokenIdTracker.SplitPosition[] memory _splitPositions,
    DytmParamStructs.AccountPosition[] memory _positions
  ) internal {
    for (uint256 i; i < _positions.length; ++i) {
      if (_positions[i].debt.debtAssets == 0) continue;

      // Approve dytmOffice to spend debt asset for repayment
      IERC20(_positions[i].debt.debtAsset).safeIncreaseAllowance(dytmOffice, _positions[i].debt.debtAssets);

      // Repay with type(uint256).max to burn all debt shares — using exact debtAssets
      // could leave 1 share of dust due to assets→shares rounding in the Office
      IDytmOffice(dytmOffice).repay(
        DytmParamStructs.RepayParams({
          account: _splitPositions[i].tokenId,
          key: _positions[i].debt.debtKey,
          withCollateralType: DytmParamStructs.TokenType.NONE,
          assets: type(uint256).max,
          shares: 0,
          extraData: ""
        })
      );

      // Reset approval — repay(max) may consume slightly less than approved debtAssets
      // due to the same assets→shares rounding
      IERC20(_positions[i].debt.debtAsset).safeApprove(dytmOffice, 0);
    }
  }
}
