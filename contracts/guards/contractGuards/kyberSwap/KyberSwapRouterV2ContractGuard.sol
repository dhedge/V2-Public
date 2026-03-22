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
// Copyright (c) 2025 dHEDGE DAO
//
// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {IMetaAggregationRouterV2} from "../../../interfaces/kyberSwap/IMetaAggregationRouterV2.sol";
import {IHasSupportedAsset} from "../../../interfaces/IHasSupportedAsset.sol";
import {IPoolManagerLogic} from "../../../interfaces/IPoolManagerLogic.sol";
import {ITransactionTypes} from "../../../interfaces/ITransactionTypes.sol";
import {SlippageAccumulator, SlippageAccumulatorUser} from "../../../utils/SlippageAccumulatorUser.sol";
import {TxDataUtils} from "../../../utils/TxDataUtils.sol";
import {SourceAssetCheckGuard} from "../SourceAssetCheckGuard.sol";

contract KyberSwapRouterV2ContractGuard is
  TxDataUtils,
  ITransactionTypes,
  SlippageAccumulatorUser,
  SourceAssetCheckGuard
{
  constructor(address _slippageAccumulator) SlippageAccumulatorUser(_slippageAccumulator) {}

  function txGuard(
    address _poolManagerLogic,
    address /* _to */,
    bytes memory _data
  ) external override returns (uint16 txType, bool) {
    address poolLogic = _accessControl(_poolManagerLogic);
    bytes4 method = getMethod(_data);
    bytes memory params = getParams(_data);

    if (method == IMetaAggregationRouterV2.swap.selector) {
      // `execution.approveTarget` is not used in MetaAggregationRouterV2::swap, only required for IMetaAggregationRouterV2::swapGeneric which we don't support
      IMetaAggregationRouterV2.SwapExecutionParams memory execution = abi.decode(
        params,
        (IMetaAggregationRouterV2.SwapExecutionParams)
      );

      txType = _verifySwap(execution.desc, poolLogic, _poolManagerLogic);
    } else if (method == IMetaAggregationRouterV2.swapSimpleMode.selector) {
      (, IMetaAggregationRouterV2.SwapDescriptionV2 memory desc, , ) = abi.decode(
        params,
        (address, IMetaAggregationRouterV2.SwapDescriptionV2, bytes, bytes)
      );

      txType = _verifySwap(desc, poolLogic, _poolManagerLogic);
    }

    return (txType, false);
  }

  function afterTxGuard(address _poolManagerLogic, address _to, bytes memory _data) public override {
    address poolLogic = IPoolManagerLogic(_poolManagerLogic).poolLogic();
    bytes4 method = getMethod(_data);
    bytes memory params = getParams(_data);

    address srcToken;
    address dstToken;

    if (method == IMetaAggregationRouterV2.swap.selector) {
      IMetaAggregationRouterV2.SwapExecutionParams memory execution = abi.decode(
        params,
        (IMetaAggregationRouterV2.SwapExecutionParams)
      );
      srcToken = execution.desc.srcToken;
      dstToken = execution.desc.dstToken;
    } else if (method == IMetaAggregationRouterV2.swapSimpleMode.selector) {
      (, IMetaAggregationRouterV2.SwapDescriptionV2 memory desc, , ) = abi.decode(
        params,
        (address, IMetaAggregationRouterV2.SwapDescriptionV2, bytes, bytes)
      );
      srcToken = desc.srcToken;
      dstToken = desc.dstToken;
    }

    if (srcToken != address(0)) {
      _checkSourceAsset(poolLogic, _poolManagerLogic, srcToken);
    }

    if (dstToken != address(0)) {
      require(IHasSupportedAsset(_poolManagerLogic).isSupportedAsset(dstToken), "unsupported destination asset");
    }

    SlippageAccumulatorUser.afterTxGuard(_poolManagerLogic, _to, _data);
  }

  function _verifySwap(
    IMetaAggregationRouterV2.SwapDescriptionV2 memory _desc,
    address _poolLogic,
    address _poolManagerLogic
  ) internal returns (uint16 txType) {
    require(_desc.dstReceiver == _poolLogic, "recipient is not pool");

    require(IHasSupportedAsset(_poolManagerLogic).isSupportedAsset(_desc.dstToken), "unsupported destination asset");

    require(_desc.feeReceivers.length == 0, "fees not supported");

    // dHEDGE vault can't sign permit message
    require(_desc.permit.length == 0, "permit not supported");

    _setSourceAsset(_poolLogic, _poolManagerLogic, _desc.srcToken);

    intermediateSwapData = SlippageAccumulator.SwapData({
      srcAsset: _desc.srcToken,
      dstAsset: _desc.dstToken,
      srcAmount: _getBalance(_desc.srcToken, _poolLogic),
      dstAmount: _getBalance(_desc.dstToken, _poolLogic)
    });

    txType = uint16(TransactionType.Exchange);
  }
}
