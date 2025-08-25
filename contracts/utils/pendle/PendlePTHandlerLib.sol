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

import {PendlePTAssetGuard} from "../../guards/assetGuards/pendle/PendlePTAssetGuard.sol";
import {IPYieldContractFactory} from "../../interfaces/pendle/IPYieldContractFactory.sol";
import {IHasGuardInfo} from "../../interfaces/IHasGuardInfo.sol";
import {IPoolLogic} from "../../interfaces/IPoolLogic.sol";
import {ISwapDataConsumingGuard} from "../../interfaces/guards/ISwapDataConsumingGuard.sol";
import {IAssetGuard} from "../../interfaces/guards/IAssetGuard.sol";
import {IPPrincipalToken} from "../../interfaces/pendle/IPPrincipalToken.sol";
import {IPActionMiscV3} from "../../interfaces/pendle/IPActionMiscV3.sol";
import {createTokenOutputSimple, createEmptyLimitOrderData} from "../../interfaces/pendle/IPAllActionTypeV3.sol";
import {IPActionMarketCoreStatic} from "../../interfaces/pendle/IPActionMarketCoreStatic.sol";
import {IPActionMintRedeemStatic} from "../../interfaces/pendle/IPActionMintRedeemStatic.sol";

library PendlePTHandlerLib {
  struct RedeemPTExecutionData {
    address pool;
    address market;
    uint256 ptAmountIn;
    address underlying;
  }

  /// @dev Same for all chains
  address public constant ROUTER_V4 = 0x888888888889758F76e7103c6CbF23ABbF58F946;

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
    (address market, address underlying) = getPTAssociatedData(_collateralAsset.asset, _pool);

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

  function getPTAssociatedData(address _pt, address _pool) internal view returns (address market, address underlying) {
    // Assuming that PendlePTAssetGuard is deployed for pendle's principal token asset type 37 and is not address(0)
    PendlePTAssetGuard pendlePTGuard = PendlePTAssetGuard(
      IHasGuardInfo(IPoolLogic(_pool).factory()).getAssetGuard(_pt)
    );

    // Calldata for pendle router requires market address, which is read from the asset guard, as no onchain interface exists to cross reference market address.
    // Asset guard requires to store associated market data for PTs.
    (market, underlying, ) = pendlePTGuard.ptAssociatedData(_pt);

    require(market != address(0), "pt not handled");
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

    (executionData.market, executionData.underlying) = getPTAssociatedData(_collateralAsset.asset, _pool);
    bool expired = IPPrincipalToken(_collateralAsset.asset).isExpired();

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
      createTokenOutputSimple(_executionData.underlying, 0),
      createEmptyLimitOrderData()
    );
  }
}
