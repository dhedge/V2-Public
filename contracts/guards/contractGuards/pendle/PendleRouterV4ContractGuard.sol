// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {IPActionSwapPTV3} from "../../../interfaces/pendle/IPActionSwapPTV3.sol";
import {IPActionMiscV3} from "../../../interfaces/pendle/IPActionMiscV3.sol";
import {IPMarket} from "../../../interfaces/pendle/IPMarket.sol";
import {IPYieldToken} from "../../../interfaces/pendle/IPYieldToken.sol";
import {IHasSupportedAsset} from "../../../interfaces/IHasSupportedAsset.sol";
import {IPoolManagerLogic} from "../../../interfaces/IPoolManagerLogic.sol";
import {ITransactionTypes} from "../../../interfaces/ITransactionTypes.sol";
import {SlippageAccumulator, SlippageAccumulatorUser} from "../../../utils/SlippageAccumulatorUser.sol";
import {TxDataUtils} from "../../../utils/TxDataUtils.sol";

import "../../../interfaces/pendle/IPAllActionTypeV3.sol" as IPAllActionTypeV3;

contract PendleRouterV4ContractGuard is TxDataUtils, ITransactionTypes, SlippageAccumulatorUser {
  /// @dev Same for all chains
  address public constant LIMIT_ROUTER = 0x000000000000c9B3E2C3Ec88B1B4c0cD853f4321;

  constructor(address _slippageAccumulator) SlippageAccumulatorUser(_slippageAccumulator) {}

  function txGuard(
    address _poolManagerLogic,
    address /* _to */,
    bytes memory _data
  ) external override returns (uint16 txType, bool) {
    address poolLogic = IPoolManagerLogic(_poolManagerLogic).poolLogic();

    // This txGuard in non view hence this check is needed
    require(msg.sender == poolLogic, "not pool logic");

    bytes4 method = getMethod(_data);

    if (method == IPActionSwapPTV3.swapExactTokenForPt.selector) {
      (
        address receiver,
        address market,
        ,
        ,
        IPAllActionTypeV3.TokenInput memory input,
        IPAllActionTypeV3.LimitOrderData memory limit
      ) = abi.decode(
          getParams(_data),
          (
            address,
            address,
            uint256,
            IPAllActionTypeV3.ApproxParams,
            IPAllActionTypeV3.TokenInput,
            IPAllActionTypeV3.LimitOrderData
          )
        );

      require(receiver == poolLogic, "recipient is not pool");

      (, address pt, ) = IPMarket(market).readTokens();

      require(IHasSupportedAsset(_poolManagerLogic).isSupportedAsset(pt), "unsupported destination asset");

      // Forbid swaps for initial version, this can be changed later
      require(input.swapData.swapType == IPAllActionTypeV3.SwapType.NONE, "only underlying");

      _validateLimitOrder(limit);

      // `tokenIn` the the token being spent, no matter what the swap type is
      intermediateSwapData = SlippageAccumulator.SwapData({
        srcAsset: input.tokenIn,
        dstAsset: pt,
        srcAmount: _getBalance(input.tokenIn, poolLogic),
        dstAmount: _getBalance(pt, poolLogic)
      });

      txType = uint16(TransactionType.BuyPendlePT);
    } else if (method == IPActionSwapPTV3.swapExactPtForToken.selector) {
      (
        address receiver,
        address market,
        ,
        IPAllActionTypeV3.TokenOutput memory output,
        IPAllActionTypeV3.LimitOrderData memory limit
      ) = abi.decode(
          getParams(_data),
          (address, address, uint256, IPAllActionTypeV3.TokenOutput, IPAllActionTypeV3.LimitOrderData)
        );

      _validateSellPendlePT(poolLogic, _poolManagerLogic, receiver, output);

      _validateLimitOrder(limit);

      (, address pt, ) = IPMarket(market).readTokens();

      // `tokenOut` the the token to receive, no matter what the swap type is
      intermediateSwapData = SlippageAccumulator.SwapData({
        srcAsset: pt,
        dstAsset: output.tokenOut,
        srcAmount: _getBalance(pt, poolLogic),
        dstAmount: _getBalance(output.tokenOut, poolLogic)
      });

      txType = uint16(TransactionType.SellPendlePT);
    } else if (method == IPActionMiscV3.exitPostExpToToken.selector) {
      // This is to sell PT token after maturity
      (address receiver, address market, , uint256 netLpIn, IPAllActionTypeV3.TokenOutput memory output) = abi.decode(
        getParams(_data),
        (address, address, uint256, uint256, IPAllActionTypeV3.TokenOutput)
      );

      _validateSellPendlePT(poolLogic, _poolManagerLogic, receiver, output);

      require(netLpIn == 0, "only PT");

      (, address pt, ) = IPMarket(market).readTokens();

      intermediateSwapData = SlippageAccumulator.SwapData({
        srcAsset: pt,
        dstAsset: output.tokenOut,
        srcAmount: _getBalance(pt, poolLogic),
        dstAmount: _getBalance(output.tokenOut, poolLogic)
      });

      txType = uint16(TransactionType.SellPendlePT);
    } else if (method == IPActionMiscV3.redeemPyToToken.selector) {
      // This is also to sell PT token after maturity
      (address receiver, address yt, , IPAllActionTypeV3.TokenOutput memory output) = abi.decode(
        getParams(_data),
        (address, address, uint256, IPAllActionTypeV3.TokenOutput)
      );

      _validateSellPendlePT(poolLogic, _poolManagerLogic, receiver, output);

      require(IPYieldToken(yt).isExpired(), "only expired");

      address pt = IPYieldToken(yt).PT();

      intermediateSwapData = SlippageAccumulator.SwapData({
        srcAsset: pt,
        dstAsset: output.tokenOut,
        srcAmount: _getBalance(pt, poolLogic),
        dstAmount: _getBalance(output.tokenOut, poolLogic)
      });

      txType = uint16(TransactionType.SellPendlePT);
    }

    return (txType, false);
  }

  function _validateLimitOrder(IPAllActionTypeV3.LimitOrderData memory _data) internal pure {
    require(_data.limitRouter == LIMIT_ROUTER || _data.limitRouter == address(0), "unknown limit router");
  }

  function _validateSellPendlePT(
    address _poolLogic,
    address _poolManagerLogic,
    address _receiver,
    IPAllActionTypeV3.TokenOutput memory _output
  ) internal view {
    require(_receiver == _poolLogic, "recipient is not pool");

    require(IHasSupportedAsset(_poolManagerLogic).isSupportedAsset(_output.tokenOut), "unsupported destination asset");

    // Forbid swaps for initial version, this can be changed later
    require(_output.swapData.swapType == IPAllActionTypeV3.SwapType.NONE, "only underlying");
  }
}
