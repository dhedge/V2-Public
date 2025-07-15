// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {SafeMath} from "@openzeppelin/contracts/math/SafeMath.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/SafeCast.sol";
import {IGmxBaseOrderUtils} from "../../../interfaces/gmx/IGmxBaseOrderUtils.sol";
import {IGmxDepositUtils} from "../../../interfaces/gmx/IGmxDepositUtils.sol";
import {IGmxDeposit} from "../../../interfaces/gmx/IGmxDeposit.sol";
import {IGmxWithdrawal} from "../../../interfaces/gmx/IGmxWithdrawal.sol";
import {IGmxWithdrawalUtils} from "../../../interfaces/gmx/IGmxWithdrawalUtils.sol";
import {IGmxExchangeRouter} from "../../../interfaces/gmx/IGmxExchangeRouter.sol";
import {IHasAssetInfo} from "../../../interfaces/IHasAssetInfo.sol";
import {IHasSupportedAsset} from "../../../interfaces/IHasSupportedAsset.sol";
import {IPoolLogic} from "../../../interfaces/IPoolLogic.sol";
import {ITransactionTypes} from "../../../interfaces/ITransactionTypes.sol";
import {IGmxDataStore} from "../../../interfaces/gmx/IGmxDataStore.sol";
import {TxDataUtils} from "../../../utils/TxDataUtils.sol";
import {ITxTrackingGuard} from "../../../interfaces/guards/ITxTrackingGuard.sol";
import {GmxDataStoreLib} from "../../../utils/gmx/GmxDataStoreLib.sol";
import {Order} from "../../../interfaces/gmx/IGmxOrder.sol";
import {IGmxReader} from "../../../interfaces/gmx/IGmxReader.sol";
import {IGmxMarket} from "../../../interfaces/gmx/IGmxMarket.sol";
import {IGmxExchangeRouterContractGuard} from "../../../interfaces/gmx/IGmxExchangeRouterContractGuard.sol";
import {IGmxEvent} from "../../../interfaces/gmx/IGmxEvent.sol";
import {GmxAfterTxValidatorLib} from "../../../utils/gmx/GmxAfterTxValidatorLib.sol";
import {GmxAfterExcutionLib} from "../../../utils/gmx/GmxAfterExcutionLib.sol";
import {IGmxReferralStorage} from "../../../interfaces/gmx/IGmxReferralStorage.sol";
import {SlippageAccumulator} from "../../../utils/SlippageAccumulator.sol";
import {DhedgeNftTrackerStorage} from "../../../utils/tracker/DhedgeNftTrackerStorage.sol";
import {GmxStructs} from "../../../utils/gmx/GmxStructs.sol";
import {GmxHelperLib} from "../../../utils/gmx/GmxHelperLib.sol";
contract GmxExchangeRouterContractGuard is
  TxDataUtils,
  ITxTrackingGuard,
  ITransactionTypes,
  IGmxExchangeRouterContractGuard
{
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
    (
      bytes4 method,
      bytes memory params,
      address poolLogic,
      GmxStructs.PoolSetting memory poolSetting
    ) = GmxAfterTxValidatorLib.validateTxGuardParams(address(this), _poolManagerLogic, _data);

    if (method == IGmxExchangeRouter.multicall.selector) {
      bytes[] memory multicallParams = abi.decode(params, (bytes[]));
      require(multicallParams.length > 0, "invalid multicall");
      bytes memory lastCallData = multicallParams[multicallParams.length - 1];
      method = getMethod(lastCallData);
      if (method == IGmxExchangeRouter.createDeposit.selector) {
        // createDeposit txs path: sendTokens(wETH), sendTokens(LongToken), sendTokens(shortToken), createDeposit
        _validateCreateDepositMulticall(_poolManagerLogic, poolSetting, _to, multicallParams);
        txType = uint16(TransactionType.GmxMulticall);
      } else if (method == IGmxExchangeRouter.createWithdrawal.selector) {
        // createWithdrawal txs path: sendTokens(wETH), sendTokens(MarketToken), createWithdrawal
        _validateCreateWithdrawalMulticall(_poolManagerLogic, poolSetting, _to, multicallParams);
        txType = uint16(TransactionType.GmxMulticall);
      } else if (method == IGmxExchangeRouter.createOrder.selector) {
        // Increase/Swap Order Types txs path: sendTokens(wETH), sendTokens(collateral), createOrder
        // Decrease Order Types txs path: sendTokens(wETH), createOrder
        require(
          _validateCreateOrderMulticall(_poolManagerLogic, poolSetting, _to, multicallParams),
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

  function afterOrderExecution(
    bytes32,
    Order.Props memory order,
    IGmxEvent.EventLogData memory eventData
  ) external override {
    GmxAfterExcutionLib.afterOrderExecutionCallback({
      order: order,
      to: gmxExchangeRouter,
      eventData: eventData,
      exchangeRouterContractGuard: address(this)
    });
  }

  function afterDepositExecution(
    bytes32,
    IGmxDeposit.Props memory deposit,
    IGmxEvent.EventLogData memory eventData
  ) external override {
    GmxAfterExcutionLib.afterDepositExecutionCallback({
      deposit: deposit,
      to: gmxExchangeRouter,
      eventData: eventData,
      exchangeRouterContractGuard: address(this)
    });
  }

  function afterWithdrawalExecution(
    bytes32,
    IGmxWithdrawal.Props memory withdrawal,
    IGmxEvent.EventLogData memory eventData
  ) external override {
    GmxAfterExcutionLib.afterWithdrawalExecutionCallback({
      withdrawal: withdrawal,
      to: gmxExchangeRouter,
      eventData: eventData,
      exchangeRouterContractGuard: address(this)
    });
  }

  function dHedgePoolsWhitelist(address poolLogic) public view override returns (GmxStructs.PoolSetting memory) {
    return _dHedgePoolsWhitelist[poolLogic];
  }

  function getVirtualTokenOracleSettings(
    address virtualToken
  ) external view override returns (GmxStructs.VirtualTokenOracleSetting memory) {
    return virtualTokenOracleSettings[virtualToken];
  }
  //multicall validations
  function _validateCreateDepositMulticall(
    address _poolManagerLogic,
    GmxStructs.PoolSetting memory _poolSetting,
    address _to,
    bytes[] memory _multicallParams
  ) internal view {
    require(_multicallParams.length == 4, "invalid multicall");
    address wntAddress = dataStore.wnt();
    address depositVaultAddress = IGmxExchangeRouter(_to).depositHandler().depositVault();
    IGmxDepositUtils.CreateDepositParams memory createDepositParams = abi.decode(
      getParams(_multicallParams[3]),
      (IGmxDepositUtils.CreateDepositParams)
    );
    _validateSendTokensTx(_poolManagerLogic, _multicallParams[0], wntAddress, depositVaultAddress);
    _validateSendTokensTx(
      _poolManagerLogic,
      _multicallParams[1],
      createDepositParams.initialLongToken,
      depositVaultAddress
    );
    _validateSendTokensTx(
      _poolManagerLogic,
      _multicallParams[2],
      createDepositParams.initialShortToken,
      depositVaultAddress
    );

    require(IHasSupportedAsset(_poolManagerLogic).isSupportedAsset(createDepositParams.market), "unsupported market");
    _validateDepositOrWithdrawalCommonParams(
      GmxStructs.DepositOrWithdrawalCommonParams({
        receiver: createDepositParams.receiver,
        callbackContract: createDepositParams.callbackContract,
        uiFeeReceiver: createDepositParams.uiFeeReceiver,
        shouldUnwrapNativeToken: createDepositParams.shouldUnwrapNativeToken,
        longTokenSwapPath: createDepositParams.longTokenSwapPath,
        shortTokenSwapPath: createDepositParams.shortTokenSwapPath
      }),
      _poolSetting.poolLogic,
      feeReceiver
    );
    _validateDepositMarketTokens(
      _poolManagerLogic,
      createDepositParams.market,
      createDepositParams.initialLongToken,
      createDepositParams.initialShortToken
    );
  }

  function _validateCreateWithdrawalMulticall(
    address _poolManagerLogic,
    GmxStructs.PoolSetting memory _poolSetting,
    address _to,
    bytes[] memory _multicallParams
  ) internal view {
    require(_multicallParams.length == 3, "invalid multicall");
    address wntAddress = dataStore.wnt();
    address withdrawalVaultAddress = IGmxExchangeRouter(_to).withdrawalHandler().withdrawalVault();
    IGmxWithdrawalUtils.CreateWithdrawalParams memory createWithdrawalParams = abi.decode(
      getParams(_multicallParams[2]),
      (IGmxWithdrawalUtils.CreateWithdrawalParams)
    );
    _validateSendTokensTx(_poolManagerLogic, _multicallParams[0], wntAddress, withdrawalVaultAddress);
    _validateSendTokensTx(
      _poolManagerLogic,
      _multicallParams[1],
      createWithdrawalParams.market,
      withdrawalVaultAddress
    );
    _validateDepositOrWithdrawalCommonParams(
      GmxStructs.DepositOrWithdrawalCommonParams({
        receiver: createWithdrawalParams.receiver,
        callbackContract: createWithdrawalParams.callbackContract,
        uiFeeReceiver: createWithdrawalParams.uiFeeReceiver,
        shouldUnwrapNativeToken: createWithdrawalParams.shouldUnwrapNativeToken,
        longTokenSwapPath: createWithdrawalParams.longTokenSwapPath,
        shortTokenSwapPath: createWithdrawalParams.shortTokenSwapPath
      }),
      _poolSetting.poolLogic,
      feeReceiver
    );
    _validateWithdrawalMarketTokens(_poolManagerLogic, createWithdrawalParams.market);
  }

  function _validateCreateOrderMulticall(
    address _poolManagerLogic,
    GmxStructs.PoolSetting memory _poolSetting,
    address _to,
    bytes[] memory _multicallParams
  ) internal view returns (bool isValidCreateOrder) {
    IGmxBaseOrderUtils.CreateOrderParams memory createOrderParams;
    uint256 numOfCalls;
    bytes memory lastCallData;
    // preliminary length check and decoding CreateOrderParams
    (lastCallData, numOfCalls, createOrderParams) = GmxAfterTxValidatorLib.decodeCreateOrder(
      address(this),
      _multicallParams
    );
    address wntAddress = dataStore.wnt();
    address orderVaultAddress = IGmxExchangeRouter(_to).orderHandler().orderVault();
    if (createOrderParams.orderType == Order.OrderType.MarketDecrease) {
      // the Decrease order types: MarketDecrease
      require(numOfCalls == 2, "invalid multicall");
      _validateSendTokensTx(_poolManagerLogic, _multicallParams[0], wntAddress, orderVaultAddress);
      _validateCreateOrderTx(_poolManagerLogic, _poolSetting, lastCallData);
      isValidCreateOrder = true;
    } else if (
      createOrderParams.orderType == Order.OrderType.MarketIncrease ||
      createOrderParams.orderType == Order.OrderType.MarketSwap
    ) {
      // the increase or swap order types: MarketIncrease or MarketSwap
      require(numOfCalls == 3, "invalid multicall");
      _validateSendTokensTx(_poolManagerLogic, _multicallParams[0], wntAddress, orderVaultAddress);
      _validateSendTokensTx(
        _poolManagerLogic,
        _multicallParams[1],
        createOrderParams.addresses.initialCollateralToken,
        orderVaultAddress
      );
      _validateCreateOrderTx(_poolManagerLogic, _poolSetting, lastCallData);
      isValidCreateOrder = true;
    }
  }

  function _validateCreateOrderTx(
    address _poolManagerLogic,
    GmxStructs.PoolSetting memory _poolSetting,
    bytes memory _subTxData
  ) internal view {
    bytes memory params = getParams(_subTxData);

    IGmxBaseOrderUtils.CreateOrderParams memory createOrderParams = abi.decode(
      params,
      (IGmxBaseOrderUtils.CreateOrderParams)
    );
    require(createOrderParams.addresses.receiver == _poolSetting.poolLogic, "invalid receiver");
    require(createOrderParams.addresses.cancellationReceiver == address(0), "invalid cancel receiver");
    require(createOrderParams.addresses.callbackContract == address(this), "invalid callback contract");
    require(createOrderParams.addresses.uiFeeReceiver == feeReceiver, "invalid fee receiver");
    require(
      IHasSupportedAsset(_poolManagerLogic).isSupportedAsset(createOrderParams.addresses.initialCollateralToken),
      "unsupported collateral"
    );
    require(createOrderParams.decreasePositionSwapType == Order.DecreasePositionSwapType.NoSwap, "invalid swap type");
    require(createOrderParams.shouldUnwrapNativeToken == false, "cannot unwrap native token");
    //Order specific validations
    if (createOrderParams.orderType == Order.OrderType.MarketSwap) {
      // only 0 can be used at createOrderParams.addresses.market for swap
      require(createOrderParams.addresses.market == address(0), "invalid market");
      _validateSwapPath(_poolManagerLogic, createOrderParams.addresses.swapPath);
      _validateMarketTokens(
        _poolManagerLogic,
        createOrderParams.addresses.swapPath[0],
        createOrderParams.addresses.initialCollateralToken
      );
    } else {
      require(
        IHasSupportedAsset(_poolManagerLogic).isSupportedAsset(createOrderParams.addresses.market),
        "unsupported market"
      );
      // swapPath not supported; swaps happen before-deposit for Increase types and after-withdraw for Decrease types;
      require(createOrderParams.addresses.swapPath.length == 0, "swap path not supported");
      _validateMarketTokens(
        _poolManagerLogic,
        createOrderParams.addresses.market,
        createOrderParams.addresses.initialCollateralToken
      );
    }

    // no check for sizeDeltaUsd, initialCollateralDeltaAmount,executionFee, triggerPrice, acceptablePrice
    //  minOutputAmount, callbackGasLimit are checked in afterTxGuard
    // not supported limit / stop-loss / take-profit yet
  }

  function _validateDepositOrWithdrawalCommonParams(
    GmxStructs.DepositOrWithdrawalCommonParams memory _commonParams,
    address _poolLogic,
    address _feeReceiver
  ) internal view {
    require(_commonParams.receiver == _poolLogic, "receiver not pool logic");
    require(_commonParams.callbackContract == address(this), "invalid callback contract");
    require(_commonParams.uiFeeReceiver == _feeReceiver, "invalid fee receiver");
    require(_commonParams.shouldUnwrapNativeToken == false, "cannot unwrap native token");
    require(_commonParams.longTokenSwapPath.length == 0, "invalid swap path");
    require(_commonParams.shortTokenSwapPath.length == 0, "invalid swap path");
  }

  function _validateMarketTokens(
    address _poolManagerLogic,
    address _market,
    address _initialCollateralToken
  ) internal view {
    IGmxMarket.Props memory marketInfo = reader.getMarket({_dataStore: dataStore, _market: _market});

    // decreaseOrder will receive pnlToken in the noSwap case
    // pnlToken can be either longToken or shortToken
    // https://github.com/gmx-io/gmx-synthetics/blob/main/contracts/position/DecreasePositionUtils.sol#L203
    // no need to check indexToken, as it may not be a token address;
    // https://github.com/gmx-io/gmx-interface/blob/master/src/config/static/markets.ts
    require(IHasSupportedAsset(_poolManagerLogic).isSupportedAsset(marketInfo.longToken), "unsupported longToken");
    require(IHasSupportedAsset(_poolManagerLogic).isSupportedAsset(marketInfo.shortToken), "unsupported shortToken");
    require(
      (_initialCollateralToken == marketInfo.longToken) || (_initialCollateralToken == marketInfo.shortToken),
      "invalid initialCollateralToken"
    );
  }

  function _validateDepositMarketTokens(
    address _poolManagerLogic,
    address _market,
    address _initialLongToken,
    address _initialShortToken
  ) internal view {
    IGmxMarket.Props memory marketInfo = reader.getMarket({_dataStore: dataStore, _market: _market});

    require(IHasSupportedAsset(_poolManagerLogic).isSupportedAsset(marketInfo.longToken), "unsupported longToken");
    require(IHasSupportedAsset(_poolManagerLogic).isSupportedAsset(marketInfo.shortToken), "unsupported shortToken");
    require(_initialLongToken == marketInfo.longToken, "invalid initialLongToken");
    require(_initialShortToken == marketInfo.shortToken, "invalid initialShortToken");
  }

  function _validateWithdrawalMarketTokens(address _poolManagerLogic, address _market) internal view {
    IGmxMarket.Props memory marketInfo = reader.getMarket({_dataStore: dataStore, _market: _market});

    require(IHasSupportedAsset(_poolManagerLogic).isSupportedAsset(marketInfo.longToken), "unsupported longToken");
    require(IHasSupportedAsset(_poolManagerLogic).isSupportedAsset(marketInfo.shortToken), "unsupported shortToken");
  }

  function _validateSwapPath(address _poolManagerLogic, address[] memory _swapPath) internal view {
    require(_swapPath.length == 1, "invalid swap path");
    require(IHasSupportedAsset(_poolManagerLogic).isSupportedAsset(_swapPath[0]), "unsupported market");
  }

  function _validateSendTokensTx(
    address _poolManagerLogic,
    bytes memory _subTxData,
    address _token,
    address _receiver
  ) internal view {
    require(getMethod(_subTxData) == IGmxExchangeRouter.sendTokens.selector, "invalid sendTokens tx");
    (address token, address receiver) = abi.decode(getParams(_subTxData), (address, address));
    require(IHasSupportedAsset(_poolManagerLogic).isSupportedAsset(token), "invalid token");
    require(token == _token, "invalid token");
    require(receiver == _receiver, "invalid receiver");
  }
}
