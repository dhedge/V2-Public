// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {SafeMath} from "@openzeppelin/contracts/math/SafeMath.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IGmxDataStore} from "../../interfaces/gmx/IGmxDataStore.sol";
import {IGmxDeposit} from "../../interfaces/gmx/IGmxDeposit.sol";
import {IGmxExchangeRouterContractGuard} from "../../interfaces/gmx/IGmxExchangeRouterContractGuard.sol";
import {IGmxMarket} from "../../interfaces/gmx/IGmxMarket.sol";
import {Order} from "../../interfaces/gmx/IGmxOrder.sol";
import {IGmxPosition} from "../../interfaces/gmx/IGmxPosition.sol";
import {IGmxReader} from "../../interfaces/gmx/IGmxReader.sol";
import {IGmxReferralStorage} from "../../interfaces/gmx/IGmxReferralStorage.sol";
import {IGmxWithdrawal} from "../../interfaces/gmx/IGmxWithdrawal.sol";
import {IHasGuardInfo} from "../../interfaces/IHasGuardInfo.sol";
import {IPoolFactory} from "../../interfaces/IPoolFactory.sol";
import {IPoolLogic} from "../../interfaces/IPoolLogic.sol";
import {IPoolManagerLogic} from "../../interfaces/IPoolManagerLogic.sol";
import {GmxClaimableCollateralTrackerLib} from "./GmxClaimableCollateralTrackerLib.sol";
import {GmxDataStoreLib} from "./GmxDataStoreLib.sol";
import {GmxPosition} from "./GmxPosition.sol";
import {GmxPositionCollateralAmountLib} from "./GmxPositionCollateralAmountLib.sol";
import {GmxPriceLib} from "./GmxPriceLib.sol";
import {GmxStructs} from "./GmxStructs.sol";

library GmxPerpMarketAssetGuardLib {
  using SafeMath for uint256;
  using GmxDataStoreLib for IGmxDataStore;

  bytes32 private constant CLAIMABLE_FUNDING_AMOUNT_DATA_STORE_KEY = keccak256(abi.encode("CLAIMABLE_FUNDING_AMOUNT"));
  bytes32 private constant ACCOUNT_DEPOSIT_LIST = keccak256(abi.encode("ACCOUNT_DEPOSIT_LIST"));

  function getBalance(address _gmxExchangeRouter, address _pool, address _asset) public view returns (uint256 balance) {
    address poolFactory = IPoolLogic(_pool).factory();
    IPoolManagerLogic poolManagerLogic = IPoolManagerLogic(IPoolLogic(_pool).poolManagerLogic());
    GmxStructs.GmxGuardData memory guardData;
    GmxPriceLib.GmxPriceDependecies memory priceDependencies;
    {
      IGmxExchangeRouterContractGuard contractguard = IGmxExchangeRouterContractGuard(
        IHasGuardInfo(poolFactory).getContractGuard(_gmxExchangeRouter)
      );
      // avoid stack too deep error
      guardData = GmxStructs.GmxGuardData({
        dataStore: contractguard.dataStore(),
        reader: contractguard.reader(),
        assetHandler: IPoolFactory(poolFactory).getAssetHandler(),
        uiFeeReceiver: contractguard.feeReceiver(),
        nftTracker: contractguard.nftTracker(),
        referralStorage: IGmxReferralStorage(contractguard.referralStorage())
      });
      priceDependencies = GmxPriceLib.GmxPriceDependecies({
        reader: guardData.reader,
        dataStore: guardData.dataStore,
        assetHandler: guardData.assetHandler,
        virtualTokenResolver: contractguard
      });
    }
    IGmxMarket.Props memory market = guardData.reader.getMarket({_dataStore: guardData.dataStore, _market: _asset});

    // 1. Collateral in the GMX positions, taking into account price impact and profit/loss
    // select positions for the market and collateralAmount > 0
    IGmxPosition.Props[] memory marketPositions = _getPositionsForMarket(
      _pool,
      guardData.reader,
      guardData.dataStore,
      _asset
    );

    if (marketPositions.length > 0) {
      bytes32[] memory positionKeys = new bytes32[](marketPositions.length);
      IGmxMarket.MarketPrices memory currentMarketPrices = IGmxMarket.MarketPrices({
        indexTokenPrice: GmxPriceLib.getTokenMinMaxPrice(priceDependencies, market.indexToken),
        longTokenPrice: GmxPriceLib.getTokenMinMaxPrice(priceDependencies, market.longToken),
        shortTokenPrice: GmxPriceLib.getTokenMinMaxPrice(priceDependencies, market.shortToken)
      });
      IGmxMarket.MarketPrices[] memory marketPrices = new IGmxMarket.MarketPrices[](marketPositions.length);
      for (uint256 i; i < marketPositions.length; i++) {
        marketPrices[i] = currentMarketPrices;
        positionKeys[i] = GmxPosition.getPositionKey(
          _pool,
          _asset,
          marketPositions[i].addresses.collateralToken,
          marketPositions[i].flags.isLong
        );
      }

      IGmxPosition.PositionInfo[] memory positionInfos = guardData.reader.getPositionInfoList({
        _dataStore: guardData.dataStore,
        _referralStorage: guardData.referralStorage,
        _positionKeys: positionKeys,
        _marketPrices: marketPrices,
        _uiFeeReceiver: guardData.uiFeeReceiver
      });

      // Collateral in the GMX positions, taking into account price impact and profit/loss
      for (uint256 i; i < positionInfos.length; i++) {
        IGmxPosition.PositionInfo memory positionInfo = positionInfos[i];
        uint256 collateralAmount = GmxPositionCollateralAmountLib.getPositionCollateralAmount(positionInfo);
        if (collateralAmount > 0) {
          balance = balance.add(
            _assetValue(poolManagerLogic, positionInfo.position.addresses.collateralToken, collateralAmount)
          );
        }
        // Claimable in the future funding fees
        if (positionInfo.fees.funding.claimableLongTokenAmount > 0) {
          balance = balance.add(
            _assetValue(poolManagerLogic, market.longToken, positionInfo.fees.funding.claimableLongTokenAmount)
          );
        }
        if (positionInfo.fees.funding.claimableShortTokenAmount > 0) {
          balance = balance.add(
            _assetValue(poolManagerLogic, market.shortToken, positionInfo.fees.funding.claimableShortTokenAmount)
          );
        }
      }
    }

    // 2. Pending orders: deposited collateral in market increase orders, plus execution fees of all orders
    IGmxReader.OrderInfo[] memory orderInfos = guardData.reader.getAccountOrders({
      _account: _pool,
      _dataStore: guardData.dataStore,
      _start: 0,
      _end: type(uint256).max
    });

    for (uint256 i; i < orderInfos.length; i++) {
      Order.Props memory order = orderInfos[i].order;
      if (
        (order.numbers.orderType == Order.OrderType.MarketIncrease && order.addresses.market == _asset) ||
        (order.numbers.orderType == Order.OrderType.MarketSwap && order.addresses.swapPath[0] == _asset) // swapPath length is always 1 for swapOrders
      ) {
        balance = balance.add(
          _assetValue(
            poolManagerLogic,
            order.addresses.initialCollateralToken,
            order.numbers.initialCollateralDeltaAmount
          )
        );
      }
      if (
        order.numbers.executionFee > 0 &&
        // check MarketSwap before indexing swapPath: non-swap orders on other markets have an empty swapPath,
        // and evaluating swapPath[0] on them would revert out-of-bounds and freeze getBalance / totalFundValue
        (order.addresses.market == _asset ||
          (order.numbers.orderType == Order.OrderType.MarketSwap && order.addresses.swapPath[0] == _asset)) // swap order
      ) {
        balance = balance.add(_assetValue(poolManagerLogic, guardData.dataStore.wnt(), order.numbers.executionFee));
      }
    }

    // 3. Funding fees that can be claimed
    uint256 fundingFeesLongToken = _getClaimableFundingFees({
      _dataStore: guardData.dataStore,
      _pool: _pool,
      _market: market.marketToken,
      _token: market.longToken
    });

    if (fundingFeesLongToken != 0) {
      balance = balance.add(_assetValue(poolManagerLogic, market.longToken, fundingFeesLongToken));
    }

    if (market.longToken != market.shortToken) {
      uint256 fundingFeesShortToken = _getClaimableFundingFees({
        _dataStore: guardData.dataStore,
        _pool: _pool,
        _market: market.marketToken,
        _token: market.shortToken
      });

      if (fundingFeesShortToken != 0) {
        balance = balance.add(_assetValue(poolManagerLogic, market.shortToken, fundingFeesShortToken));
      }
    }

    // 4. Collateral in a deposit vault
    bytes32[] memory depositKeys = guardData.dataStore.getBytes32ValuesAt(
      keccak256(abi.encode(ACCOUNT_DEPOSIT_LIST, _pool)),
      0,
      type(uint256).max
    );

    for (uint256 i; i < depositKeys.length; i++) {
      IGmxDeposit.Props memory deposit = guardData.reader.getDeposit({
        _dataStore: guardData.dataStore,
        key: depositKeys[i]
      });
      // ACCOUNT_DEPOSIT_LIST holds the pool's pending deposits across all markets; only count this market's,
      // otherwise a single pending deposit is counted once per supported GMX market and inflates the balance
      if (deposit.addresses.market != _asset) {
        continue;
      }
      balance = balance.add(_assetValue(poolManagerLogic, guardData.dataStore.wnt(), deposit.numbers.executionFee));
      balance = balance.add(
        _assetValue(poolManagerLogic, deposit.addresses.initialLongToken, deposit.numbers.initialLongTokenAmount)
      );
      balance = balance.add(
        _assetValue(poolManagerLogic, deposit.addresses.initialShortToken, deposit.numbers.initialShortTokenAmount)
      );
    }

    // 5. LP token balance
    uint256 lpTokenBalance = IERC20(_asset).balanceOf(_pool);
    if (lpTokenBalance > 0) {
      balance = balance.add(
        GmxPriceLib.getMarketLpTokenPrice(priceDependencies, market, false).mul(lpTokenBalance).div(1e18)
      );
    }

    // 6. Market tokens in a withdrawal vault
    balance = balance.add(_balanceWithdrawalVault(_pool, poolManagerLogic, market, priceDependencies));

    // 7. claimable collateral
    balance = balance.add(
      GmxClaimableCollateralTrackerLib.balanceClaimableCollateral(_pool, poolManagerLogic, market, guardData)
    );
  }

  function _getClaimableFundingFees(
    IGmxDataStore _dataStore,
    address _pool,
    address _market,
    address _token
  ) private view returns (uint256 claimableFundingFees) {
    claimableFundingFees = _dataStore.getUint(
      keccak256(abi.encode(CLAIMABLE_FUNDING_AMOUNT_DATA_STORE_KEY, _market, _token, _pool))
    );
  }

  function _assetValue(
    IPoolManagerLogic _poolManagerLogic,
    address _token,
    uint256 _amount
  ) private view returns (uint256 assetValue) {
    assetValue = _poolManagerLogic.assetValue(_token, _amount);
  }

  function _balanceWithdrawalVault(
    address _pool,
    IPoolManagerLogic _poolManagerLogic,
    IGmxMarket.Props memory _market,
    GmxPriceLib.GmxPriceDependecies memory _priceDependencies
  ) private view returns (uint256 balance) {
    bytes32[] memory withdrawalKeys = _priceDependencies.dataStore.getBytes32ValuesAt(
      GmxDataStoreLib.accountWithdrawalListKey(_pool),
      0,
      type(uint256).max
    );

    for (uint256 i; i < withdrawalKeys.length; i++) {
      IGmxWithdrawal.Props memory withdrawal = _priceDependencies.reader.getWithdrawal({
        _dataStore: _priceDependencies.dataStore,
        key: withdrawalKeys[i]
      });
      // ACCOUNT_WITHDRAWAL_LIST holds the pool's pending withdrawals across all markets; only count this market's.
      // Otherwise the execution fee is counted once per supported market and marketTokenAmount is valued with the
      // wrong market's LP price (below priced against `_market`, which is only correct for this market's withdrawals).
      if (withdrawal.addresses.market != _market.marketToken) {
        continue;
      }
      balance = balance.add(
        _assetValue(_poolManagerLogic, _priceDependencies.dataStore.wnt(), withdrawal.numbers.executionFee)
      );
      balance = balance.add(
        GmxPriceLib
          .getMarketLpTokenPrice(_priceDependencies, _market, false)
          .mul(withdrawal.numbers.marketTokenAmount)
          .div(1e18)
      );
    }
  }

  function _getPositionsForMarket(
    address _account,
    IGmxReader _reader,
    IGmxDataStore _dataStore,
    address _market
  ) private view returns (IGmxPosition.Props[] memory marketPositions) {
    IGmxPosition.Props[] memory positions = _reader.getAccountPositions({
      _account: _account,
      _dataStore: _dataStore,
      _start: 0,
      _end: type(uint256).max
    });
    marketPositions = new IGmxPosition.Props[](positions.length);
    uint256 index = 0;

    for (uint256 i; i < positions.length; i++) {
      if (positions[i].numbers.collateralAmount > 0 && positions[i].addresses.market == _market) {
        marketPositions[index] = positions[i];
        index++;
      }
    }

    uint256 reduceLength = positions.length.sub(index);
    assembly {
      mstore(marketPositions, sub(mload(marketPositions), reduceLength))
    }
  }
}
