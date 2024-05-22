// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {FlatcoinModuleKeys} from "../../../utils/flatMoney/libraries/FlatcoinModuleKeys.sol";
import {IDelayerOrder} from "../../../interfaces/flatMoney/IDelayerOrder.sol";
import {IFlatcoinVault} from "../../../interfaces/flatMoney/IFlatcoinVault.sol";
import {IGuard} from "../../../interfaces/guards/IGuard.sol";
import {IHasSupportedAsset} from "../../../interfaces/IHasSupportedAsset.sol";
import {IPoolManagerLogic} from "../../../interfaces/IPoolManagerLogic.sol";
import {ITransactionTypes} from "../../../interfaces/ITransactionTypes.sol";
import {TxDataUtils} from "../../../utils/TxDataUtils.sol";

/// @notice Allows buying and selling FlatMoney's flatcoin UNIT.
contract FlatMoneyDelayedOrderContractGuard is IGuard, ITransactionTypes, TxDataUtils {
  /// @notice Transaction guard for FlatMoney's DelayedOrder contract.
  /// @dev Whitelisting `cancelExistingOrder` is a must to be able to retrieve funds from the DelayedOrder contract
  /// @dev in case something wents wrong with the order.
  /// @dev Experiment: not emitting any events, because I've never seen their use case yet.
  /// @param _poolManagerLogic Address of the PoolManagerLogic contract
  /// @param _to DelayerOrder contract address
  /// @param _data Transaction data payload
  /// @return txType The transaction type of a given transaction data
  /// @return isPublic If the transaction is public or private
  function txGuard(
    address _poolManagerLogic,
    address _to,
    bytes memory _data
  ) external view override returns (uint16 txType, bool) {
    address poolLogic = IPoolManagerLogic(_poolManagerLogic).poolLogic();

    require(msg.sender == poolLogic, "not pool logic");

    bytes4 method = getMethod(_data);

    if (method == IDelayerOrder.announceStableDeposit.selector) {
      IFlatcoinVault vault = IDelayerOrder(_to).vault();
      address stableModule = vault.moduleAddress(FlatcoinModuleKeys._STABLE_MODULE_KEY);

      require(IHasSupportedAsset(_poolManagerLogic).isSupportedAsset(stableModule), "unsupported destination asset");

      txType = uint16(TransactionType.FlatMoneyStableDeposit);
    } else if (method == IDelayerOrder.announceStableWithdraw.selector) {
      IFlatcoinVault vault = IDelayerOrder(_to).vault();
      address collateralAsset = vault.collateral();

      require(IHasSupportedAsset(_poolManagerLogic).isSupportedAsset(collateralAsset), "unsupported destination asset");

      txType = uint16(TransactionType.FlatMoneyStableWithdraw);
    } else if (method == IDelayerOrder.cancelExistingOrder.selector) {
      txType = uint16(TransactionType.FlatMoneyCancelOrder);
    }

    return (txType, false);
  }
}
