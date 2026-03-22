// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {SafeMath} from "@openzeppelin/contracts/math/SafeMath.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/SafeCast.sol";
import {IGmxExchangeRouter} from "../../../interfaces/gmx/IGmxExchangeRouter.sol";
import {IHasAssetInfo} from "../../../interfaces/IHasAssetInfo.sol";
import {IHasSupportedAsset} from "../../../interfaces/IHasSupportedAsset.sol";
import {IPoolLogic} from "../../../interfaces/IPoolLogic.sol";
import {ITransactionTypes} from "../../../interfaces/ITransactionTypes.sol";
import {IGmxDataStore} from "../../../interfaces/gmx/IGmxDataStore.sol";
import {ITxTrackingGuard} from "../../../interfaces/guards/ITxTrackingGuard.sol";
import {GmxDataStoreLib} from "../../../utils/gmx/GmxDataStoreLib.sol";
import {IGmxReader} from "../../../interfaces/gmx/IGmxReader.sol";
import {IGmxExchangeRouterContractGuard} from "../../../interfaces/gmx/IGmxExchangeRouterContractGuard.sol";
import {GmxEventUtils} from "../../../utils/gmx/GmxEventUtils.sol";
import {GmxAfterTxValidatorLib} from "../../../utils/gmx/GmxAfterTxValidatorLib.sol";
import {GmxAfterExecutionLib} from "../../../utils/gmx/GmxAfterExecutionLib.sol";
import {IGmxReferralStorage} from "../../../interfaces/gmx/IGmxReferralStorage.sol";
import {SlippageAccumulator} from "../../../utils/SlippageAccumulator.sol";
import {DhedgeNftTrackerStorage} from "../../../utils/tracker/DhedgeNftTrackerStorage.sol";
import {GmxStructs} from "../../../utils/gmx/GmxStructs.sol";
import {GmxHelperLib} from "../../../utils/gmx/GmxHelperLib.sol";

contract GmxExchangeRouterContractGuard is ITxTrackingGuard, ITransactionTypes, IGmxExchangeRouterContractGuard {
  using SafeMath for uint256;
  using SafeCast for uint256;
  using GmxDataStoreLib for IGmxDataStore;

  address public immutable override gmxExchangeRouter;
  address public immutable override feeReceiver;
  IGmxDataStore public immutable override dataStore;
  IGmxReader public immutable override reader;
  IGmxReferralStorage public immutable override referralStorage;
  SlippageAccumulator public immutable override slippageAccumulator;
  DhedgeNftTrackerStorage public immutable override nftTracker;

  bool public override isTxTrackingGuard = true;

  mapping(address => GmxStructs.PoolSetting) private _dHedgePoolsWhitelist;
  mapping(address => GmxStructs.VirtualTokenOracleSetting) public virtualTokenOracleSettings; // virtualToken => tokenOracleSetting, for oracle price resolution

  constructor(
    GmxStructs.GmxContractGuardConfig memory _config,
    GmxStructs.PoolSetting[] memory _whitelisteddHedgePools,
    GmxStructs.VirtualTokenOracleSetting[] memory _virtualTokenOracleSettings,
    address _slippageAccumulator,
    address _nftTracker
  ) {
    gmxExchangeRouter = _config.gmxExchangeRouter;
    feeReceiver = _config.feeReceiver;
    dataStore = IGmxDataStore(_config.dataStore);
    reader = IGmxReader(_config.reader);
    referralStorage = IGmxReferralStorage(_config.referralStorage);
    nftTracker = DhedgeNftTrackerStorage(_nftTracker);
    slippageAccumulator = SlippageAccumulator(_slippageAccumulator);

    for (uint256 i; i < _whitelisteddHedgePools.length; ++i) {
      GmxStructs.PoolSetting memory poolSetting = _whitelisteddHedgePools[i];
      address poolFactory = IPoolLogic(poolSetting.poolLogic).factory();
      require(
        poolSetting.withdrawalAsset != address(0) &&
          IHasAssetInfo(poolFactory).isValidAsset(poolSetting.withdrawalAsset),
        "invalid asset"
      );
      _dHedgePoolsWhitelist[poolSetting.poolLogic] = poolSetting;
    }
    for (uint256 i; i < _virtualTokenOracleSettings.length; ++i) {
      virtualTokenOracleSettings[_virtualTokenOracleSettings[i].virtualToken] = _virtualTokenOracleSettings[i];
    }
  }

  function txGuard(
    address _poolManagerLogic,
    address _to,
    bytes memory _data
  ) external view override returns (uint16 txType, bool) {
    (bytes4 method, bytes memory params, address poolLogic, GmxStructs.PoolSetting memory poolSetting) = GmxHelperLib
      .validateTxGuardParams(address(this), _poolManagerLogic, _data);

    if (method == IGmxExchangeRouter.multicall.selector) {
      bytes[] memory multicallParams = abi.decode(params, (bytes[]));
      require(multicallParams.length > 0, "invalid multicall");
      bytes memory lastCallData = multicallParams[multicallParams.length - 1];
      method = GmxHelperLib.getMethod(lastCallData);
      if (method == IGmxExchangeRouter.createDeposit.selector) {
        // createDeposit txs path: sendTokens(wETH), sendTokens(LongToken), sendTokens(shortToken), createDeposit
        GmxHelperLib.validateCreateDepositMulticall(
          _poolManagerLogic,
          poolSetting,
          _to,
          multicallParams,
          reader,
          dataStore,
          feeReceiver
        );
        txType = uint16(TransactionType.GmxMulticall);
      } else if (method == IGmxExchangeRouter.createWithdrawal.selector) {
        // createWithdrawal txs path: sendTokens(wETH), sendTokens(MarketToken), createWithdrawal
        GmxHelperLib.validateCreateWithdrawalMulticall(
          _poolManagerLogic,
          poolSetting,
          _to,
          multicallParams,
          reader,
          dataStore,
          feeReceiver
        );
        txType = uint16(TransactionType.GmxMulticall);
      } else if (method == IGmxExchangeRouter.createOrder.selector) {
        // Increase/Swap Order Types txs path: sendTokens(wETH), sendTokens(collateral), createOrder
        // Decrease Order Types txs path: sendTokens(wETH), createOrder
        require(
          GmxHelperLib.validateCreateOrderMulticall(
            _poolManagerLogic,
            poolSetting,
            _to,
            multicallParams,
            reader,
            dataStore,
            feeReceiver
          ),
          "invalid multicall"
        );
        txType = uint16(TransactionType.GmxMulticall);
      }
    } else if (method == IGmxExchangeRouter.claimFundingFees.selector) {
      (address[] memory markets, address[] memory tokens, address receiver) = abi.decode(
        params,
        (address[], address[], address)
      );
      GmxHelperLib.checkMarketsAndTokensSupportedForClaiming({
        exchangeRouterContractGuard: address(this),
        poolManagerLogic: _poolManagerLogic,
        tokens: tokens,
        markets: markets
      });
      require(receiver == poolLogic, "invalid receiver");
      txType = uint16(TransactionType.GmxClaimFundingFees);
    } else if (method == IGmxExchangeRouter.claimCollateral.selector) {
      (address[] memory markets, address[] memory tokens, , address receiver) = abi.decode(
        params,
        (address[], address[], uint256[], address)
      );
      GmxHelperLib.checkMarketsAndTokensSupportedForClaiming({
        exchangeRouterContractGuard: address(this),
        poolManagerLogic: _poolManagerLogic,
        tokens: tokens,
        markets: markets
      });
      require(receiver == poolLogic, "invalid receiver");
      txType = uint16(TransactionType.GmxClaimCollateral);
    } else if (method == IGmxExchangeRouter.cancelOrder.selector) {
      GmxHelperLib.validateCancelOrder(address(this), _poolManagerLogic, params);
      txType = uint16(TransactionType.GmxCancelOrder);
    } else if (method == IGmxExchangeRouter.cancelDeposit.selector) {
      GmxHelperLib.validateCancelDeposit(address(this), _poolManagerLogic, params);
      txType = uint16(TransactionType.GmxCancelDeposit);
    } else if (method == IGmxExchangeRouter.cancelWithdrawal.selector) {
      txType = uint16(TransactionType.GmxCancelWithdrawal);
      require(IHasSupportedAsset(_poolManagerLogic).isSupportedAsset(dataStore.wnt()), "unsupported wnt");
    }
    // IGmxExchangeRouter.updateOrder is for limit orders, not supported yet
    return (txType, false);
  }

  function afterTxGuard(address _poolManagerLogic, address _to, bytes memory _data) public override {
    GmxAfterTxValidatorLib.afterTxGuardCheck(address(this), _poolManagerLogic, _to, _data);
  }

  function dHedgePoolsWhitelist(address poolLogic) public view override returns (GmxStructs.PoolSetting memory) {
    return _dHedgePoolsWhitelist[poolLogic];
  }

  function getVirtualTokenOracleSettings(
    address virtualToken
  ) external view override returns (GmxStructs.VirtualTokenOracleSetting memory) {
    return virtualTokenOracleSettings[virtualToken];
  }

  // v2.2
  function afterOrderExecution(
    bytes32,
    GmxEventUtils.EventLogData memory orderData,
    GmxEventUtils.EventLogData memory eventData
  ) external override {
    GmxAfterExecutionLib.afterOrderExecutionCallback({
      orderData: orderData,
      to: gmxExchangeRouter,
      eventData: eventData,
      exchangeRouterContractGuard: address(this)
    });
  }

  // v2.2
  function afterDepositExecution(
    bytes32,
    GmxEventUtils.EventLogData memory depositData,
    GmxEventUtils.EventLogData memory eventData
  ) external override {
    GmxAfterExecutionLib.afterDepositExecutionCallback({
      depositData: depositData,
      to: gmxExchangeRouter,
      eventData: eventData,
      exchangeRouterContractGuard: address(this)
    });
  }

  // v2.2
  function afterWithdrawalExecution(
    bytes32,
    GmxEventUtils.EventLogData memory withdrawalData,
    GmxEventUtils.EventLogData memory eventData
  ) external override {
    GmxAfterExecutionLib.afterWithdrawalExecutionCallback({
      withdrawalData: withdrawalData,
      to: gmxExchangeRouter,
      eventData: eventData,
      exchangeRouterContractGuard: address(this)
    });
  }
}
