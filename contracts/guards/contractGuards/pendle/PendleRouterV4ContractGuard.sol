// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {SafeMath} from "@openzeppelin/contracts/math/SafeMath.sol";

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
  using SafeMath for uint256;

  /// @dev Same for all chains
  address public constant LIMIT_ROUTER = 0x000000000000c9B3E2C3Ec88B1B4c0cD853f4321;

  /// @dev Hard per-transaction bound on the vault value a single manager-initiated PT swap may give up, measured
  ///      from AssetHandler oracle prices. Pendle settles a limit order at a maker-signed rate with no oracle band,
  ///      so this actual-value check is the only thing preventing a manager from self-filling an order at a price
  ///      they choose and draining the pool. Applies to the AMM path too. 50 = 0.5%.
  uint256 internal constant MAX_PENDLE_SWAP_SLIPPAGE_BPS = 50;
  uint256 internal constant BPS_DENOMINATOR = 10_000;

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

      (address pt, address yt) = _validateMarket(market, _poolManagerLogic);

      // Forbid swaps for initial version, this can be changed later
      require(input.swapData.swapType == IPAllActionTypeV3.SwapType.NONE, "only underlying");

      // Buying PT: normal fills are makers selling PT for SY, flash fills are makers minting YT from SY.
      _validateLimitOrder(limit, yt, IPAllActionTypeV3.OrderType.PT_FOR_SY, IPAllActionTypeV3.OrderType.SY_FOR_YT);

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

      (address pt, address yt) = _validateMarket(market, _poolManagerLogic);

      _validateSellPendlePT(poolLogic, _poolManagerLogic, receiver, output);

      // Selling PT: normal fills are makers buying PT with SY, flash fills are makers redeeming YT for SY.
      _validateLimitOrder(limit, yt, IPAllActionTypeV3.OrderType.SY_FOR_PT, IPAllActionTypeV3.OrderType.YT_FOR_SY);

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

      (address pt, ) = _validateMarket(market, _poolManagerLogic);

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

    // Bound the value surrendered by a manager-initiated PT swap. This is the only economic check on a limit
    // order: Pendle fills at a maker-signed rate with no oracle band, so without it a manager could self-fill at
    // an arbitrary price and drain the pool. Redemptions are excluded — a post-expiry PT unwinds ~1:1 to the
    // accounting asset and is not single-transaction price-manipulable.
    if (
      method == IPActionSwapPTV3.swapExactTokenForPt.selector || method == IPActionSwapPTV3.swapExactPtForToken.selector
    ) {
      _enforceMaxSwapSlippage(_accessControl(_poolManagerLogic));
    }

    SlippageAccumulatorUser.afterTxGuard(_poolManagerLogic, _to, _data);
  }

  /// @dev Reverts if the destination value received is worth less than the source value spent minus the max
  ///      allowed slippage, both priced from AssetHandler oracles. Reuses the balance deltas the slippage
  ///      accumulator reads (prior balances stored in `intermediateSwapData` by `txGuard`). Trades that gain
  ///      value pass. Cross-multiplied to keep integer precision.
  function _enforceMaxSwapSlippage(address _poolLogic) internal view {
    uint256 srcSpent = intermediateSwapData.srcAmount.sub(_getBalance(intermediateSwapData.srcAsset, _poolLogic));
    uint256 dstReceived = _getBalance(intermediateSwapData.dstAsset, _poolLogic).sub(intermediateSwapData.dstAmount);

    uint256 srcValue = slippageAccumulator.assetValue(intermediateSwapData.srcAsset, srcSpent);
    uint256 dstValue = slippageAccumulator.assetValue(intermediateSwapData.dstAsset, dstReceived);

    require(
      dstValue.mul(BPS_DENOMINATOR) >= srcValue.mul(BPS_DENOMINATOR.sub(MAX_PENDLE_SWAP_SLIPPAGE_BPS)),
      "swap slippage too high"
    );
  }

  /// @dev Structural checks on the limit order block. These do not prove the signed price is fair — that is the
  ///      job of the post-execution actual-value bound in `_enforceMaxSwapSlippage` — they only pin every fill to
  ///      the correct market, direction, and settlement shape so that bound is measured against the right legs.
  function _validateLimitOrder(
    IPAllActionTypeV3.LimitOrderData memory _data,
    address _yt,
    IPAllActionTypeV3.OrderType _normalFillType,
    IPAllActionTypeV3.OrderType _flashFillType
  ) internal pure {
    // A positive remainder must always continue through the selected market. A non-zero epsilon lets Pendle skip
    // the market leg and route the remainder to the fill receiver, which for a sell is the SY contract.
    require(_data.epsSkipMarket == 0, "eps skip market not zero");

    require(_data.limitRouter == LIMIT_ROUTER || _data.limitRouter == address(0), "unknown limit router");

    // Pendle decides whether to route through the limit order protocol from the fill arrays alone, `limitRouter`
    // is not part of its emptiness check, so fills must not be allowed to pass with a zero router address.
    // https://github.com/pendle-finance/pendle-core-v2-public/blob/main/contracts/router/base/ActionBase.sol#L366
    if (_data.normalFills.length + _data.flashFills.length == 0) return;

    require(_data.limitRouter == LIMIT_ROUTER, "unknown limit router");

    _validateFills(_data.normalFills, _yt, _normalFillType);
    _validateFills(_data.flashFills, _yt, _flashFillType);
  }

  /// @dev Each order carries its own YT, and Pendle derives the PT and SY actually settled from it rather than from
  ///      the market being swapped against. Markets sharing an SY (same underlying, different maturities) would
  ///      otherwise let a fill deliver a foreign PT which still counts towards the router's `minPtOut` check.
  ///      The order type is pinned so a fill cannot settle the opposite direction, and a zero maker token is
  ///      rejected to keep Pendle's transfer helper from routing a native-value callback into the pool.
  function _validateFills(
    IPAllActionTypeV3.FillOrderParams[] memory _fills,
    address _yt,
    IPAllActionTypeV3.OrderType _expectedType
  ) internal pure {
    for (uint256 i; i < _fills.length; ++i) {
      require(_fills[i].order.YT == _yt, "invalid yt");
      require(_fills[i].order.orderType == _expectedType, "invalid order type");
      require(_fills[i].order.token != address(0), "invalid maker token");
    }
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

  function _validateMarket(address _market, address _poolManagerLogic) internal view returns (address pt, address yt) {
    (, pt, yt) = IPMarket(_market).readTokens();
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
