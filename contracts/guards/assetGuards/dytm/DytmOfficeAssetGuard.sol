// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {SafeMath} from "@openzeppelin/contracts/math/SafeMath.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/SafeCast.sol";
import {ClosedAssetGuard} from "../ClosedAssetGuard.sol";
import {IDytmPeriphery} from "../../../interfaces/dytm/IDytmPeriphery.sol";
import {DytmParamStructs} from "../../../utils/dytm/DytmParamStructs.sol";
import {IDytmAccountSplitterAndMerger} from "../../../interfaces/dytm/IDytmAccountSplitterAndMerger.sol";
import {IDytmOffice} from "../../../interfaces/dytm/IDytmOffice.sol";
import {IDytmDelegatee} from "../../../interfaces/dytm/IDytmDelegatee.sol";
import {DytmSplitTokenIdTracker} from "./DytmSplitTokenIdTracker.sol";
import {DytmSwapDataCalculator} from "./DytmSwapDataCalculator.sol";
import {DytmHelperLib} from "../../../utils/dytm/DytmHelperLib.sol";
import {IPoolLogic} from "../../../interfaces/IPoolLogic.sol";
import {ISwapDataConsumingGuard} from "../../../interfaces/guards/ISwapDataConsumingGuard.sol";
import {IAddAssetCheckGuard} from "../../../interfaces/guards/IAddAssetCheckGuard.sol";
import {IHasSupportedAsset} from "../../../interfaces/IHasSupportedAsset.sol";

/// @title Dytm Office Asset Guard
/// @dev Asset type = 106
contract DytmOfficeAssetGuard is
  ClosedAssetGuard,
  DytmSplitTokenIdTracker,
  DytmSwapDataCalculator,
  ISwapDataConsumingGuard,
  IAddAssetCheckGuard
{
  using SafeMath for uint256;
  using SafeCast for uint256;

  bool public override isAddAssetCheckGuard = true;

  function addAssetCheck(address _poolLogic, IHasSupportedAsset.Asset calldata _asset) external view override {
    require(!_asset.isDeposit, "deposit not supported");
    require(_useContractGuard().poolsWhitelist(_poolLogic), "pool not whitelisted");
  }

  /// @param _mismatchDeltaNumerator Numerator for mismatch delta tolerance
  /// @param _pendleStaticRouter Pendle static router address for PT conversion
  /// @param _dytmOffice DYTM Office address
  /// @param _poolFactory dHEDGE pool factory address
  /// @param _dytmPeriphery DYTM Periphery address
  /// @param _accountSplitterAndMerger Account splitter and merger address
  /// @param _dytmWithdrawProcessor DYTM withdraw processor address
  constructor(
    uint256 _mismatchDeltaNumerator,
    address _pendleStaticRouter,
    address _dytmOffice,
    address _poolFactory,
    address _dytmPeriphery,
    address _accountSplitterAndMerger,
    address _dytmWithdrawProcessor
  )
    DytmSwapDataCalculator(
      _mismatchDeltaNumerator,
      _pendleStaticRouter,
      _dytmOffice,
      _poolFactory,
      _dytmPeriphery,
      _accountSplitterAndMerger,
      _dytmWithdrawProcessor
    )
  {}

  /// @notice Returns the balance of the Dytm Office User Account of the pool
  /// @dev Returns the balance to be priced in USD
  /// @param _pool PoolLogic address
  /// @return balance Dytm Office User Account balance of the pool
  function getBalance(address _pool, address) public view override returns (uint256 balance) {
    uint256[] memory marketIds = _useContractGuard().getOwnedTokenIds(_pool);
    for (uint256 i; i < marketIds.length; ++i) {
      DytmParamStructs.AccountPosition memory position = IDytmPeriphery(dytmPeriphery).getAccountPosition({
        account: DytmHelperLib.toUserAccount(_pool),
        market: uint88(marketIds[i])
      });
      if (position.isHealthy) {
        balance = balance.add(position.totalCollateralValueUSD).sub(position.debt.debtValueUSD);
      }
    }
  }

  /// @notice Returns decimal of the dytm office asset
  /// @dev Returns decimal 18 (USD pricing)
  function getDecimals(address) external pure override returns (uint256 decimals) {
    decimals = 18;
  }

  /// @notice Calculates swap data parameters for DYTM withdrawal (ISwapDataConsumingGuard interface)
  function calculateSwapDataParams(
    address _pool,
    uint256 _poolTokenAmount,
    uint256 _slippageTolerance
  ) public override(DytmSwapDataCalculator, ISwapDataConsumingGuard) returns (SwapDataParams memory params) {
    return DytmSwapDataCalculator.calculateSwapDataParams(_pool, _poolTokenAmount, _slippageTolerance);
  }

  /// @notice Process withdrawal for DYTM positions (IComplexAssetGuard variant)
  /// @dev Called by PoolLogic when ComplexAsset.withdrawData is non-empty.
  ///      Delegates to the internal implementation (withdrawData is used later by DytmWithdrawLib).
  function withdrawProcessing(
    address _pool,
    address _asset,
    uint256 _portion,
    address _to,
    bytes memory // _withdrawData — consumed by DytmWithdrawLib in easySwapperV2 withdrawalVault during unrollAssets, not here
  ) external override returns (address withdrawAsset, uint256 withdrawBalance, MultiTransaction[] memory transactions) {
    return _withdrawProcessingInternal(_pool, _asset, _portion, _to);
  }

  /// @notice Process withdrawal for DYTM positions
  /// @dev Splits accounts proportionally and transfers isolated accounts to withdrawer
  /// @param _pool Pool address
  /// @param _asset DYTM Office address
  /// @param _portion Portion to withdraw (in 1e18 scale, e.g., 1e18 = 100%)
  /// @param _to Recipient address
  /// @return withdrawAsset Asset to withdraw (always address(0) for DYTM)
  /// @return withdrawBalance Balance to withdraw (always 0 for DYTM)
  /// @return transactions Array of transactions to execute for account splitting and transfer
  function withdrawProcessing(
    address _pool,
    address _asset,
    uint256 _portion,
    address _to
  )
    external
    virtual
    override
    returns (address withdrawAsset, uint256 withdrawBalance, MultiTransaction[] memory transactions)
  {
    return _withdrawProcessingInternal(_pool, _asset, _portion, _to);
  }

  /// @dev Internal implementation for withdraw processing, shared by both overloads
  function _withdrawProcessingInternal(
    address _pool,
    address _asset,
    uint256 _portion,
    address _to
  ) internal returns (address withdrawAsset, uint256 withdrawBalance, MultiTransaction[] memory transactions) {
    uint256 newAccountIdCount = uint256(IDytmOffice(dytmOffice).getAccountCount()).add(1);
    uint256[] memory marketIds = _useContractGuard().getOwnedTokenIds(_pool);

    _accessControl(IPoolLogic(_pool).poolManagerLogic(), poolFactory);

    // Reset previously tracked split token IDs
    _resetSplitTokenIds(_to);

    transactions = new MultiTransaction[](marketIds.length.mul(2));
    uint256 txCount;
    uint256 accountId = DytmHelperLib.toUserAccount(_pool);
    uint64 fraction = _portion.toUint64();

    for (uint256 i; i < marketIds.length; ++i) {
      uint88 marketId = uint88(marketIds[i]);

      // Check if position is healthy and has collateral
      (bool isWithdrawable, ) = _isPositionWithdrawable(_pool, marketId, dytmPeriphery);
      if (!isWithdrawable) {
        continue;
      }

      {
        // Prepare split account parameters
        bytes memory callbackData = abi.encode(
          IDytmAccountSplitterAndMerger.CallbackData({
            operation: IDytmAccountSplitterAndMerger.Operation.SPLIT_ACCOUNT,
            data: abi.encode(
              IDytmAccountSplitterAndMerger.SplitAccountParams({
                fraction: fraction,
                sourceAccount: accountId,
                market: marketId
              })
            )
          })
        );

        // Transaction 1: Split account to create isolated account with portion of assets/debts
        transactions[txCount].to = _asset;
        transactions[txCount].txData = abi.encodeWithSelector(
          IDytmOffice.delegationCall.selector,
          DytmParamStructs.DelegationCallParams({
            callbackData: callbackData,
            delegatee: IDytmDelegatee(accountSplitterAndMerger)
          })
        );
        ++txCount;
      }

      // Transaction 2: Transfer the split isolated account to the withdrawer
      transactions[txCount].to = _asset; // DYTM Office address
      transactions[txCount].txData = abi.encodeWithSelector(
        IDytmOffice.transfer.selector,
        _to,
        _addSplitTokenId(_to, newAccountIdCount, marketId), // Track split token ID and market ID
        1
      );
      ++txCount;
      newAccountIdCount = newAccountIdCount.add(1);
    }

    // Reduce array length to remove empty transaction slots
    uint256 reduceLength = transactions.length.sub(txCount);
    assembly {
      mstore(transactions, sub(mload(transactions), reduceLength))
    }

    return (withdrawAsset, withdrawBalance, transactions);
  }
}
