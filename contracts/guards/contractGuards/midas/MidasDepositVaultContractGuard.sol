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
// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {IHasSupportedAsset} from "../../../interfaces/IHasSupportedAsset.sol";
import {IMidasDepositVault} from "../../../interfaces/midas/IMidasDepositVault.sol";
import {ITransactionTypes} from "../../../interfaces/ITransactionTypes.sol";
import {SlippageAccumulator, SlippageAccumulatorUser} from "../../../utils/SlippageAccumulatorUser.sol";
import {TxDataUtils} from "../../../utils/TxDataUtils.sol";

/// @title MidasDepositVaultContractGuard
/// @notice Contract guard for a Midas DepositVault. Allows a manager to atomically mint an mToken
///         (e.g. mAPOLLO) to the pool via `depositInstant`, while blocking custom-recipient and
///         asynchronous request variants so minted tokens always land in the pool.
/// @dev `depositInstant` output is checked against the shared `SlippageAccumulator` using measured
///      pre/post balance deltas (the manager-supplied `minReceiveAmount` is not trusted).
contract MidasDepositVaultContractGuard is TxDataUtils, ITransactionTypes, SlippageAccumulatorUser {
  constructor(address _slippageAccumulator) SlippageAccumulatorUser(_slippageAccumulator) {}

  /// @notice Validates a manager transaction routed to a Midas DepositVault.
  /// @param _poolManagerLogic Pool manager logic address.
  /// @param _to The DepositVault being called.
  /// @param _data Calldata of the transaction.
  /// @return txType Transaction type (Exchange) when allowed.
  /// @return isPublic Always false (manager-only).
  function txGuard(
    address _poolManagerLogic,
    address _to,
    bytes memory _data
  ) external override returns (uint16 txType, bool isPublic) {
    address poolLogic = _accessControl(_poolManagerLogic);

    // Only the atomic, self-recipient `depositInstant` is permitted. Every other method (the
    // custom-recipient overload and the async `depositRequest` variants) falls through, leaving
    // `txType` at 0 so `PoolLogic.execTransaction` reverts downstream.
    if (getMethod(_data) == IMidasDepositVault.depositInstant.selector) {
      // `tokenIn` is the first argument of `depositInstant`.
      address tokenIn = convert32toAddress(getInput(_data, 0));
      address mToken = IMidasDepositVault(_to).mToken();

      // The token being spent and the minted mToken must both be accounted by the pool.
      require(IHasSupportedAsset(_poolManagerLogic).isSupportedAsset(tokenIn), "unsupported source asset");
      require(IHasSupportedAsset(_poolManagerLogic).isSupportedAsset(mToken), "unsupported destination asset");

      // Record pre-execution balances; the inherited `afterTxGuard` measures the actual delta.
      intermediateSwapData = SlippageAccumulator.SwapData({
        srcAsset: tokenIn,
        dstAsset: mToken,
        srcAmount: _getBalance(tokenIn, poolLogic),
        dstAmount: _getBalance(mToken, poolLogic)
      });

      txType = uint16(TransactionType.Exchange);
    }

    return (txType, false);
  }
}
