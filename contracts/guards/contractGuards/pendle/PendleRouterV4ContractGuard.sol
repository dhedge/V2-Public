// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {PendlePTAssetGuard} from "../../../guards/assetGuards/pendle/PendlePTAssetGuard.sol";
import {IPActionSwapPTV3} from "../../../interfaces/pendle/IPActionSwapPTV3.sol";
import {IPActionMiscV3} from "../../../interfaces/pendle/IPActionMiscV3.sol";
import {IPMarket} from "../../../interfaces/pendle/IPMarket.sol";
import {IPYieldToken} from "../../../interfaces/pendle/IPYieldToken.sol";
import {IHasGuardInfo} from "../../../interfaces/IHasGuardInfo.sol";
import {IHasSupportedAsset} from "../../../interfaces/IHasSupportedAsset.sol";
import {ITransactionTypes} from "../../../interfaces/ITransactionTypes.sol";
import {SlippageAccumulator, SlippageAccumulatorUser} from "../../../utils/SlippageAccumulatorUser.sol";
import {TxDataUtils} from "../../../utils/TxDataUtils.sol";

import "../../../interfaces/pendle/IPAllActionTypeV3.sol" as IPAllActionTypeV3;

contract PendleRouterV4ContractGuard is TxDataUtils, ITransactionTypes, SlippageAccumulatorUser {
  /// @dev Same for all chains
  address public constant LIMIT_ROUTER = 0x000000000000c9B3E2C3Ec88B1B4c0cD853f4321;

  IHasGuardInfo public immutable poolFactory;

  constructor(address _slippageAccumulator, address _poolFactory) SlippageAccumulatorUser(_slippageAccumulator) {
    require(_poolFactory != address(0), "invalid address");

    poolFactory = IHasGuardInfo(_poolFactory);
  }

  function txGuard(
    address _poolManagerLogic,
    address /* _to */,
    bytes memory _data
  ) public virtual override returns (uint16 txType, bool) {
    address poolLogic = _accessControl(_poolManagerLogic);
    bytes4 method = getMethod(_data);
    bytes memory params = getParams(_data);

    if (method == IPActionSwapPTV3.swapExactTokenForPt.selector) {
      (
        address receiver,
        address market,
        IPAllActionTypeV3.TokenInput memory input,
        IPAllActionTypeV3.LimitOrderData memory limit
      ) = _decodeSwapExactTokenForPt(params);

      require(receiver == poolLogic, "recipient is not pool");

      require(IHasSupportedAsset(_poolManagerLogic).isSupportedAsset(input.tokenIn), "unsupported source asset");

      address pt = _validateMarket(market, _poolManagerLogic);

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
        IPAllActionTypeV3.TokenOutput memory output,
        IPAllActionTypeV3.LimitOrderData memory limit
      ) = _decodeSwapExactPtForToken(params);

      address pt = _validateMarket(market, _poolManagerLogic);

      _validateSellPendlePT(poolLogic, _poolManagerLogic, receiver, output);

      _validateLimitOrder(limit);

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
      (
        address receiver,
        address market,
        uint256 netLpIn,
        IPAllActionTypeV3.TokenOutput memory output
      ) = _decodeExitPostExpToToken(params);

      address pt = _validateMarket(market, _poolManagerLogic);

      _validateSellPendlePT(poolLogic, _poolManagerLogic, receiver, output);

      require(netLpIn == 0, "only pt");

      intermediateSwapData = SlippageAccumulator.SwapData({
        srcAsset: pt,
        dstAsset: output.tokenOut,
        srcAmount: _getBalance(pt, poolLogic),
        dstAmount: _getBalance(output.tokenOut, poolLogic)
      });

      txType = uint16(TransactionType.SellPendlePT);
    } else if (method == IPActionMiscV3.redeemPyToToken.selector) {
      // This is also to sell PT token after maturity
      (address receiver, address yt, IPAllActionTypeV3.TokenOutput memory output) = _decodeRedeemPyToToken(params);

      _validateSellPendlePT(poolLogic, _poolManagerLogic, receiver, output);

      address pt = IPYieldToken(yt).PT();
      (, , address storedYt) = PendlePTAssetGuard(poolFactory.getAssetGuard(pt)).ptAssociatedData(pt);

      require(yt == storedYt, "invalid yt");

      require(IPYieldToken(yt).isExpired(), "only expired");

      require(IHasSupportedAsset(_poolManagerLogic).isSupportedAsset(pt), "pt not enabled");

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

  function afterTxGuard(address _poolManagerLogic, address _to, bytes memory _data) public virtual override {
    bytes4 method = getMethod(_data);
    bytes memory params = getParams(_data);

    address srcToken;
    address dstToken;

    if (method == IPActionSwapPTV3.swapExactTokenForPt.selector) {
      (, address market, IPAllActionTypeV3.TokenInput memory input, ) = _decodeSwapExactTokenForPt(params);
      (, dstToken, ) = IPMarket(market).readTokens();
      srcToken = input.tokenIn;
    } else if (method == IPActionSwapPTV3.swapExactPtForToken.selector) {
      (, address market, IPAllActionTypeV3.TokenOutput memory output, ) = _decodeSwapExactPtForToken(params);
      (, srcToken, ) = IPMarket(market).readTokens();
      dstToken = output.tokenOut;
    } else if (method == IPActionMiscV3.exitPostExpToToken.selector) {
      (, address market, , IPAllActionTypeV3.TokenOutput memory output) = _decodeExitPostExpToToken(params);
      (, srcToken, ) = IPMarket(market).readTokens();
      dstToken = output.tokenOut;
    } else if (method == IPActionMiscV3.redeemPyToToken.selector) {
      (, address yt, IPAllActionTypeV3.TokenOutput memory output) = _decodeRedeemPyToToken(params);
      srcToken = IPYieldToken(yt).PT();
      dstToken = output.tokenOut;
    }

    if (srcToken != address(0)) {
      require(IHasSupportedAsset(_poolManagerLogic).isSupportedAsset(srcToken), "unsupported source asset");
    }

    if (dstToken != address(0)) {
      require(IHasSupportedAsset(_poolManagerLogic).isSupportedAsset(dstToken), "unsupported destination asset");
    }

    SlippageAccumulatorUser.afterTxGuard(_poolManagerLogic, _to, _data);
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

    // Not related to SY sUSDe and USDe, but by looking at the code it's possible to set `tokenRedeemSy` different from `tokenOut` if SY supports multiple tokens out
    // Example: https://etherscan.io/address/0xac0047886a985071476a1186be89222659970d65#readContract#F12
    require(_output.tokenOut == _output.tokenRedeemSy, "tokenOut mismatch");

    require(IHasSupportedAsset(_poolManagerLogic).isSupportedAsset(_output.tokenOut), "unsupported destination asset");

    // Forbid swaps for initial version, this can be changed later
    require(_output.swapData.swapType == IPAllActionTypeV3.SwapType.NONE, "only underlying");
  }

  function _validateMarket(address _market, address _poolManagerLogic) internal view returns (address pt) {
    (, pt, ) = IPMarket(_market).readTokens();
    (address storedMarket, , ) = PendlePTAssetGuard(poolFactory.getAssetGuard(pt)).ptAssociatedData(pt);

    require(_market == storedMarket, "invalid market");

    require(IHasSupportedAsset(_poolManagerLogic).isSupportedAsset(pt), "pt not enabled");
  }

  function _decodeSwapExactTokenForPt(
    bytes memory _params
  )
    internal
    pure
    returns (
      address receiver,
      address market,
      IPAllActionTypeV3.TokenInput memory input,
      IPAllActionTypeV3.LimitOrderData memory limit
    )
  {
    (receiver, market, , , input, limit) = abi.decode(
      _params,
      (
        address,
        address,
        uint256,
        IPAllActionTypeV3.ApproxParams,
        IPAllActionTypeV3.TokenInput,
        IPAllActionTypeV3.LimitOrderData
      )
    );
  }

  function _decodeSwapExactPtForToken(
    bytes memory _params
  )
    internal
    pure
    returns (
      address receiver,
      address market,
      IPAllActionTypeV3.TokenOutput memory output,
      IPAllActionTypeV3.LimitOrderData memory limit
    )
  {
    (receiver, market, , output, limit) = abi.decode(
      _params,
      (address, address, uint256, IPAllActionTypeV3.TokenOutput, IPAllActionTypeV3.LimitOrderData)
    );
  }

  function _decodeExitPostExpToToken(
    bytes memory _params
  )
    internal
    pure
    returns (address receiver, address market, uint256 netLpIn, IPAllActionTypeV3.TokenOutput memory output)
  {
    (receiver, market, , netLpIn, output) = abi.decode(
      _params,
      (address, address, uint256, uint256, IPAllActionTypeV3.TokenOutput)
    );
  }

  function _decodeRedeemPyToToken(
    bytes memory _params
  ) internal pure returns (address receiver, address yt, IPAllActionTypeV3.TokenOutput memory output) {
    (receiver, yt, , output) = abi.decode(_params, (address, address, uint256, IPAllActionTypeV3.TokenOutput));
  }
}
