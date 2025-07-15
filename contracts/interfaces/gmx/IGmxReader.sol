// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {Order} from "./IGmxOrder.sol";
import {IGmxPosition} from "./IGmxPosition.sol";
import {IGmxDataStore} from "./IGmxDataStore.sol";
import {IGmxDeposit} from "./IGmxDeposit.sol";
import {IGmxWithdrawal} from "./IGmxWithdrawal.sol";
import {IGmxMarket} from "./IGmxMarket.sol";
import {IGmxPrice} from "./IGmxPrice.sol";
import {IGmxReferralStorage} from "./IGmxReferralStorage.sol";
import {IGmxMarketPoolValueInfo} from "./IGmxMarketPoolValueInfo.sol";
import {IGmxSwapPricingUtils} from "./IGmxSwapPricingUtils.sol";

interface IGmxReader {
  function getOrder(IGmxDataStore _dataStore, bytes32 _orderKey) external view returns (Order.Props memory order_);

  function getAccountPositions(
    IGmxDataStore _dataStore,
    address _account,
    uint256 _start,
    uint256 _end
  ) external view returns (IGmxPosition.Props[] memory positions_);

  function getMarket(IGmxDataStore _dataStore, address _market) external view returns (IGmxMarket.Props memory market_);

  function getAccountOrders(
    IGmxDataStore _dataStore,
    address _account,
    uint256 _start,
    uint256 _end
  ) external view returns (Order.Props[] memory orders_);

  function getAccountPositionInfoList(
    IGmxDataStore _dataStore,
    IGmxReferralStorage _referralStorage,
    address _account,
    address[] memory _markets,
    IGmxMarket.MarketPrices[] memory _marketPrices,
    address _uiFeeReceiver,
    uint256 _start,
    uint256 _end
  ) external view returns (IGmxPosition.PositionInfo[] memory positionInfos_);

  function getPositionInfoList(
    IGmxDataStore _dataStore,
    IGmxReferralStorage _referralStorage,
    bytes32[] memory _positionKeys,
    IGmxMarket.MarketPrices[] memory _marketPrices,
    address _uiFeeReceiver
  ) external view returns (IGmxPosition.PositionInfo[] memory positionInfos_);

  function getPosition(IGmxDataStore _dataStore, bytes32 _key) external view returns (IGmxPosition.Props memory);

  function getPositionInfo(
    IGmxDataStore _dataStore,
    IGmxReferralStorage _referralStorage,
    bytes32 _positionKey,
    IGmxMarket.MarketPrices memory _marketPrices,
    uint256 _sizeDeltaUsd,
    address _uiFeeReceiver,
    bool _usePositionSizeAsSizeDeltaUsd
  ) external view returns (IGmxPosition.PositionInfo memory);

  function getDeposit(IGmxDataStore _dataStore, bytes32 key) external view returns (IGmxDeposit.Props memory);

  function getWithdrawal(IGmxDataStore _dataStore, bytes32 key) external view returns (IGmxWithdrawal.Props memory);

  function getMarketTokenPrice(
    IGmxDataStore _dataStore,
    IGmxMarket.Props memory _market,
    IGmxPrice.Price memory _indexTokenPrice,
    IGmxPrice.Price memory _longTokenPrice,
    IGmxPrice.Price memory _shortTokenPrice,
    bytes32 _pnlFactorType,
    bool _maximize
  ) external view returns (int256, IGmxMarketPoolValueInfo.Props memory);

  function getDepositAmountOut(
    IGmxDataStore dataStore,
    IGmxMarket.Props memory market,
    IGmxMarket.MarketPrices memory prices,
    uint256 longTokenAmount,
    uint256 shortTokenAmount,
    address uiFeeReceiver,
    IGmxSwapPricingUtils.SwapPricingType swapPricingType,
    bool includeVirtualInventoryImpact
  ) external view returns (uint256);

  function getWithdrawalAmountOut(
    IGmxDataStore dataStore,
    IGmxMarket.Props memory market,
    IGmxMarket.MarketPrices memory prices,
    uint256 marketTokenAmount,
    address uiFeeReceiver,
    IGmxSwapPricingUtils.SwapPricingType swapPricingType
  ) external view returns (uint256, uint256);
}
