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
// Copyright (c) 2024 dHEDGE DAO
//
// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {SafeMath} from "@openzeppelin/contracts/math/SafeMath.sol";

import {PendlePTAssetGuard} from "../../guards/assetGuards/pendle/PendlePTAssetGuard.sol";
import {IPYieldContractFactory} from "../../interfaces/pendle/IPYieldContractFactory.sol";
import {IAssetHandler} from "../../interfaces/IAssetHandler.sol";
import {IERC20Extended} from "../../interfaces/IERC20Extended.sol";
import {IHasGuardInfo} from "../../interfaces/IHasGuardInfo.sol";
import {IPoolFactory} from "../../interfaces/IPoolFactory.sol";
import {IPoolLogic} from "../../interfaces/IPoolLogic.sol";
import {ISwapDataConsumingGuard} from "../../interfaces/guards/ISwapDataConsumingGuard.sol";
import {IAssetGuard} from "../../interfaces/guards/IAssetGuard.sol";
import {IPPrincipalToken} from "../../interfaces/pendle/IPPrincipalToken.sol";
import {IPActionMiscV3} from "../../interfaces/pendle/IPActionMiscV3.sol";
import {createTokenOutputSimple, createEmptyLimitOrderData} from "../../interfaces/pendle/IPAllActionTypeV3.sol";
import {IPActionMarketCoreStatic} from "../../interfaces/pendle/IPActionMarketCoreStatic.sol";
import {IPActionMintRedeemStatic} from "../../interfaces/pendle/IPActionMintRedeemStatic.sol";
import {IPMarket, MarketState} from "../../interfaces/pendle/IPMarket.sol";
import {PendleLogExpMath} from "./PendleLogExpMath.sol";

library PendlePTHandlerLib {
  using SafeMath for uint256;

  struct RedeemPTExecutionData {
    address pool;
    address market;
    uint256 ptAmountIn;
    address underlying;
    uint256 minTokenOut;
  }

  /// @dev Same for all chains
  address public constant ROUTER_V4 = 0x888888888889758F76e7103c6CbF23ABbF58F946;

  uint256 internal constant BPS_DENOMINATOR = 10_000;
  /// @dev Annualisation basis (365 days in seconds) used by Pendle's MarketMathCore to express
  ///      lnFeeRateRoot. Hardcoded constant in their library, not configurable on-chain.
  uint256 internal constant IMPLIED_RATE_TIME = 365 days;

  /// @dev Residual tolerance applied on top of the dynamic Pendle AMM fee when computing minTokenOut
  ///      for a non-expired PT unroll. Defends against minor cross-block price drift.
  uint256 internal constant PT_UNROLL_RESIDUAL_SLIPPAGE_BPS = 10;

  function detectPendlePT(
    ISwapDataConsumingGuard.AssetStructure memory _collateralAsset,
    address _pendleYieldContractFactory
  ) internal view returns (bool isPT) {
    if (_pendleYieldContractFactory == address(0)) return false;

    return IPYieldContractFactory(_pendleYieldContractFactory).isPT(_collateralAsset.asset);
  }

  /// @dev Mutates passed _collateralAsset in place
  function convertPendlePTToUnderlying(
    ISwapDataConsumingGuard.AssetStructure memory _collateralAsset,
    address _pool,
    address _pendleStaticRouter
  ) internal view {
    convertPendlePTToUnderlyingByFactory(_collateralAsset, IPoolLogic(_pool).factory(), _pendleStaticRouter);
  }

  /// @dev Mutates passed _collateralAsset in place. Accepts factory address directly.
  function convertPendlePTToUnderlyingByFactory(
    ISwapDataConsumingGuard.AssetStructure memory _collateralAsset,
    address _factory,
    address _pendleStaticRouter
  ) internal view {
    (address market, address underlying) = getPTAssociatedDataByFactory(_collateralAsset.asset, _factory);

    bool expired = IPPrincipalToken(_collateralAsset.asset).isExpired();

    // When exiting from PT which is not expired, there is a fee associated. Using `swapExactPtForSyStatic` allows to approximate net amount out with fee deducted.
    // When PT is expired fee is 0, however there might be cases when PT is not being redeemed 1:1 to underlying, so we always call static router to get the amount out.
    // `redeemPyToSyStatic` can be used to get the estimated amount out for expired PTs, because when expired, no YT needs to be burned.
    if (expired) {
      _collateralAsset.amount = IPActionMintRedeemStatic(_pendleStaticRouter).redeemPyToSyStatic(
        IPPrincipalToken(_collateralAsset.asset).YT(),
        _collateralAsset.amount
      );
    } else {
      (_collateralAsset.amount, , , ) = IPActionMarketCoreStatic(_pendleStaticRouter).swapExactPtForSyStatic(
        market,
        _collateralAsset.amount
      );
    }

    _collateralAsset.asset = underlying;
  }

  function getPTAssociatedDataByFactory(
    address _pt,
    address _factory
  ) internal view returns (address market, address underlying) {
    // Assuming that PendlePTAssetGuard is deployed for pendle's principal token asset type 37 and is not address(0)
    PendlePTAssetGuard pendlePTGuard = PendlePTAssetGuard(IHasGuardInfo(_factory).getAssetGuard(_pt));

    // Calldata for pendle router requires market address, which is read from the asset guard, as no onchain interface exists to cross reference market address.
    // Asset guard requires to store associated market data for PTs.
    (market, underlying, ) = pendlePTGuard.ptAssociatedData(_pt);

    require(market != address(0), "pt not handled");
  }

  /// @dev Computes `minTokenOut` for a non-expired PT unroll from AssetHandler USD prices (Pendle
  ///      Chainlink TWAP for PT, Chainlink for the output token), applies the dynamic Pendle AMM fee
  ///      derived from the market's `lnFeeRateRoot`, and adds a small residual tolerance.
  function computeMinTokenOutPreExp(
    address _pt,
    uint256 _ptAmountIn,
    address _tokenOut,
    address _factory,
    address _market
  ) internal view returns (uint256 minTokenOut) {
    uint256 expected = _getExpectedTokenOut(_pt, _ptAmountIn, _tokenOut, _factory);
    uint256 feeRate = _getFeeRate(_market);
    // Divide by feeRate (>=1e18) to account for the AMM swap fee, then apply residual tolerance
    minTokenOut = expected.mul(1e18).div(feeRate).mul(BPS_DENOMINATOR - PT_UNROLL_RESIDUAL_SLIPPAGE_BPS).div(
      BPS_DENOMINATOR
    );
  }

  /// @dev Mutates passed _transactions in place
  function processTransactions(
    ISwapDataConsumingGuard.AssetStructure memory _collateralAsset,
    IAssetGuard.MultiTransaction[] memory _transactions,
    uint256 _txCount,
    address _pool
  ) internal view returns (uint256) {
    _transactions[_txCount].to = _collateralAsset.asset;
    _transactions[_txCount].txData = abi.encodeWithSelector(
      IPoolLogic.approve.selector,
      ROUTER_V4,
      _collateralAsset.amount
    );
    _txCount++;

    RedeemPTExecutionData memory executionData;
    executionData.pool = _pool;
    executionData.ptAmountIn = _collateralAsset.amount;

    address factory = IPoolLogic(_pool).factory();
    (executionData.market, executionData.underlying) = getPTAssociatedDataByFactory(_collateralAsset.asset, factory);
    bool expired = IPPrincipalToken(_collateralAsset.asset).isExpired();

    // Expired path keeps minTokenOut == 0: Pendle's post-expiry redemption rate is not single-tx manipulable.
    if (!expired) {
      executionData.minTokenOut = computeMinTokenOutPreExp(
        _collateralAsset.asset,
        executionData.ptAmountIn,
        executionData.underlying,
        factory,
        executionData.market
      );
    }

    _transactions[_txCount].to = ROUTER_V4;
    _transactions[_txCount].txData = expired ? _getPostExpTxData(executionData) : _getPreExpTxData(executionData);
    _txCount++;

    return _txCount;
  }

  function _getPostExpTxData(RedeemPTExecutionData memory _executionData) internal pure returns (bytes memory txData) {
    txData = abi.encodeWithSelector(
      IPActionMiscV3.exitPostExpToToken.selector,
      _executionData.pool,
      _executionData.market,
      _executionData.ptAmountIn,
      0,
      createTokenOutputSimple(_executionData.underlying, 0)
    );
  }

  function _getPreExpTxData(RedeemPTExecutionData memory _executionData) internal pure returns (bytes memory txData) {
    txData = abi.encodeWithSelector(
      IPActionMiscV3.exitPreExpToToken.selector,
      _executionData.pool,
      _executionData.market,
      _executionData.ptAmountIn,
      0,
      0,
      createTokenOutputSimple(_executionData.underlying, _executionData.minTokenOut),
      createEmptyLimitOrderData()
    );
  }

  /// @dev Converts PT amount to expected token output amount using AssetHandler USD prices.
  function _getExpectedTokenOut(
    address _pt,
    uint256 _ptAmountIn,
    address _tokenOut,
    address _factory
  ) private view returns (uint256) {
    IAssetHandler assetHandler = IAssetHandler(IPoolFactory(_factory).getAssetHandler());
    return
      _ptAmountIn
        .mul(assetHandler.getUSDPrice(_pt))
        .div(10 ** IERC20Extended(_pt).decimals())
        .mul(10 ** IERC20Extended(_tokenOut).decimals())
        .div(assetHandler.getUSDPrice(_tokenOut));
  }

  /// @dev Computes the Pendle AMM fee rate for the market by replicating MarketMathCore logic:
  ///      feeRate = exp(lnFeeRateRoot * timeToExpiry / IMPLIED_RATE_TIME)
  ///      Returns 1e18-scale value (1e18 = no fee, >1e18 = fee applied).
  function _getFeeRate(address _market) private view returns (uint256) {
    MarketState memory state = IPMarket(_market).readState(ROUTER_V4);
    uint256 timeToExpiry = state.expiry.sub(block.timestamp);
    // lnFeeRateRoot is the annualised ln of the fee exchange rate. Scale it to the remaining
    // time-to-expiry to obtain the continuously-compounded fee exponent for the current period.
    uint256 lnFeeExponent = state.lnFeeRateRoot.mul(timeToExpiry).div(IMPLIED_RATE_TIME);
    // Exponentiate to get the fee multiplier (1e18 = 1x, values >1e18 mean output is divided down)
    return uint256(PendleLogExpMath.exp(int256(lnFeeExponent)));
  }
}
