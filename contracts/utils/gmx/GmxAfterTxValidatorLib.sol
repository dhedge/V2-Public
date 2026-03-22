// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {IGmxDeposit} from "../../interfaces/gmx/IGmxDeposit.sol";
import {IGmxWithdrawal} from "../../interfaces/gmx/IGmxWithdrawal.sol";
import {IGmxDataStore} from "../../interfaces/gmx/IGmxDataStore.sol";
import {IGmxReader} from "../../interfaces/gmx/IGmxReader.sol";
import {IGmxReferralStorage} from "../../interfaces/gmx/IGmxReferralStorage.sol";
import {IGmxMarket} from "../../interfaces/gmx/IGmxMarket.sol";
import {Order} from "../../interfaces/gmx/IGmxOrder.sol";
import {IPoolManagerLogic} from "../../interfaces/IPoolManagerLogic.sol";
import {GmxPriceLib} from "./GmxPriceLib.sol";
import {SafeMath} from "@openzeppelin/contracts/math/SafeMath.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/SafeCast.sol";
import {IGmxPosition} from "../../interfaces/gmx/IGmxPosition.sol";
import {IGmxExchangeRouterContractGuard} from "../../interfaces/gmx/IGmxExchangeRouterContractGuard.sol";
import {GmxPosition} from "./GmxPosition.sol";
import {IPoolFactory} from "../../interfaces/IPoolFactory.sol";
import {IGmxExchangeRouter} from "../../interfaces/gmx/IGmxExchangeRouter.sol";
import {SlippageAccumulator} from "../SlippageAccumulator.sol";
import {GmxDataStoreLib} from "./GmxDataStoreLib.sol";
import {IGmxVirtualTokenResolver} from "../../interfaces/gmx/IGmxVirtualTokenResolver.sol";
import {GmxClaimableCollateralTrackerLib} from "./GmxClaimableCollateralTrackerLib.sol";
import {GmxPositionCollateralAmountLib} from "./GmxPositionCollateralAmountLib.sol";
import {DhedgeNftTrackerStorage} from "../tracker/DhedgeNftTrackerStorage.sol";
import {GmxHelperLib} from "./GmxHelperLib.sol";
import {GmxStructs} from "../../utils/gmx/GmxStructs.sol";

library GmxAfterTxValidatorLib {
  using SafeMath for uint256;
  using SafeCast for uint256;
  using GmxDataStoreLib for IGmxDataStore;

  // Maximum leverage which is allowed to reduce risk of liquidation
  uint256 public constant MAX_LEVERAGE = 7e18; // 18 decimals
  uint256 public constant MAX_SLIPPAGE = 150; // slippage, 10_000 = 100%, 100 = 1%, 10 = 0.1%, 1 = 0.01%
  uint128 private constant SCALING_FACTOR = 1e6; // for slippageAccumulator calculation
  uint256 public constant CALLBACK_GAS_LIMIT = 750_000; // gas limit for callback

  struct ContractGuardVars {
    IGmxDataStore dataStore;
    IGmxReader reader;
    SlippageAccumulator slippageAccumulator;
    DhedgeNftTrackerStorage nftTracker;
    address assetHandler;
  }

  // get positionCollateralAmount, accounting the position's pnl
  // https://github.com/gmx-io/gmx-synthetics/blob/main/contracts/position/PositionUtils.sol#L396C1-L400C44
  function _getExistingPosition(
    Order.Props memory latestOrder,
    GmxPriceLib.GmxPriceDependecies memory priceDependencies,
    IGmxReferralStorage referralStorage,
    address feeReceiver
  ) internal view returns (IGmxPosition.Props memory position, uint256 positionCollateralAmount) {
    bytes32 positionKey = GmxPosition.getPositionKey(
      latestOrder.addresses.account,
      latestOrder.addresses.market,
      latestOrder.addresses.initialCollateralToken,
      latestOrder.flags.isLong
    );
    position = priceDependencies.reader.getPosition(priceDependencies.dataStore, positionKey);
    if (position.addresses.account == address(0)) {
      // check account to determine if there is an existing position
      //  https://github.com/gmx-io/gmx-synthetics/blob/main/contracts/reader/ReaderPositionUtils.sol#L188
      return (position, 0);
    }

    IGmxMarket.Props memory market = priceDependencies.reader.getMarket({
      _dataStore: priceDependencies.dataStore,
      _market: latestOrder.addresses.market
    });
    IGmxMarket.MarketPrices memory currentMarketPrices = IGmxMarket.MarketPrices({
      indexTokenPrice: GmxPriceLib.getTokenMinMaxPrice(priceDependencies, market.indexToken),
      longTokenPrice: GmxPriceLib.getTokenMinMaxPrice(priceDependencies, market.longToken),
      shortTokenPrice: GmxPriceLib.getTokenMinMaxPrice(priceDependencies, market.shortToken)
    });

    // https://github.com/gmx-io/gmx-synthetics/blob/main/contracts/reader/ReaderPositionUtils.sol#L101
    IGmxPosition.PositionInfo memory positionInfo = priceDependencies.reader.getPositionInfo({
      _dataStore: priceDependencies.dataStore,
      _referralStorage: referralStorage,
      _positionKey: positionKey,
      _marketPrices: currentMarketPrices,
      _sizeDeltaUsd: 0,
      _uiFeeReceiver: feeReceiver,
      _usePositionSizeAsSizeDeltaUsd: true
    });
    positionCollateralAmount = GmxPositionCollateralAmountLib.getPositionCollateralAmount(positionInfo);
  }

  function maxLeverageCheck(
    Order.Props memory latestOrder,
    GmxPriceLib.GmxPriceDependecies memory priceDependencies,
    address exchangeRouterContractGuard
  ) public view {
    //max increase leverage check
    (IGmxPosition.Props memory position, uint256 positionCollateralAmount) = _getExistingPosition(
      latestOrder,
      priceDependencies,
      IGmxExchangeRouterContractGuard(exchangeRouterContractGuard).referralStorage(),
      IGmxExchangeRouterContractGuard(exchangeRouterContractGuard).feeReceiver()
    );

    uint256 collateralPrice = GmxPriceLib
      .getTokenMinMaxPrice(priceDependencies, latestOrder.addresses.initialCollateralToken)
      .min;
    uint256 currentLeverage;
    uint256 newLeverage;
    if (positionCollateralAmount > 0) {
      currentLeverage = position.numbers.sizeInUsd.mul(1e18).div(positionCollateralAmount.mul(collateralPrice));
    }
    // only allow OrderType: MarketDecrease and MarketIncrease, for now
    if (latestOrder.numbers.orderType == Order.OrderType.MarketDecrease) {
      //
      if (latestOrder.numbers.sizeDeltaUsd >= position.numbers.sizeInUsd) {
        // close position
        return;
      }
      if (latestOrder.numbers.initialCollateralDeltaAmount >= positionCollateralAmount) {
        // the sizeInUsd > 0 at this point, so does not make sense to withdraw all collateral
        revert("invalid collateralDeltaAmount");
      }
      newLeverage = position.numbers.sizeInUsd.sub(latestOrder.numbers.sizeDeltaUsd).mul(1e18).div(
        positionCollateralAmount.sub(latestOrder.numbers.initialCollateralDeltaAmount).mul(collateralPrice)
      );
    } else if (latestOrder.numbers.orderType == Order.OrderType.MarketIncrease) {
      if (positionCollateralAmount.add(latestOrder.numbers.initialCollateralDeltaAmount) > 0) {
        newLeverage = position.numbers.sizeInUsd.add(latestOrder.numbers.sizeDeltaUsd).mul(1e18).div(
          positionCollateralAmount.add(latestOrder.numbers.initialCollateralDeltaAmount).mul(collateralPrice)
        );
      }
    }
    if (newLeverage > currentLeverage) {
      require(newLeverage <= MAX_LEVERAGE, "max leverage exceeded");
    }
  }

  function getAssetHandler(address poolManagerLogic) public view returns (address) {
    return IPoolFactory(IPoolManagerLogic(poolManagerLogic).factory()).getAssetHandler();
  }

  function _checkSlippage(
    SlippageAccumulator slippageAccumulator,
    address poolManagerLogic,
    SlippageAccumulator.SwapData memory swapData
  ) internal view {
    // using USDPriceAggregator
    if (swapData.dstAmount < swapData.srcAmount) {
      require(swapData.dstAmount >= swapData.srcAmount.mul(10_000 - MAX_SLIPPAGE).div(10_000), "high slippage");
      uint128 newSlippage = swapData
        .srcAmount
        .sub(swapData.dstAmount)
        .mul(SCALING_FACTOR)
        .div(swapData.srcAmount)
        .toUint128();
      uint128 maxSlippageCap = slippageAccumulator.maxCumulativeSlippage();
      uint128 cumulativeSlippageImpact = slippageAccumulator.getCumulativeSlippageImpact(poolManagerLogic);
      require(uint256(newSlippage).add(cumulativeSlippageImpact).toUint128() <= maxSlippageCap, "high slippage");
    }
  }

  function afterTxGuardCheck(
    address exchangeRouterContractGuard,
    address poolManagerLogic,
    address to,
    bytes memory data
  ) external {
    (bytes4 method, bytes memory params, , ) = GmxHelperLib.validateTxGuardParams(
      exchangeRouterContractGuard,
      poolManagerLogic,
      data
    );
    ContractGuardVars memory contractGuardVars;
    GmxPriceLib.GmxPriceDependecies memory priceDependencies;
    {
      contractGuardVars = ContractGuardVars({
        dataStore: IGmxExchangeRouterContractGuard(exchangeRouterContractGuard).dataStore(),
        reader: IGmxExchangeRouterContractGuard(exchangeRouterContractGuard).reader(),
        slippageAccumulator: IGmxExchangeRouterContractGuard(exchangeRouterContractGuard).slippageAccumulator(),
        nftTracker: IGmxExchangeRouterContractGuard(exchangeRouterContractGuard).nftTracker(),
        assetHandler: getAssetHandler(poolManagerLogic)
      });
      priceDependencies = GmxPriceLib.GmxPriceDependecies({
        reader: contractGuardVars.reader,
        dataStore: contractGuardVars.dataStore,
        assetHandler: contractGuardVars.assetHandler,
        virtualTokenResolver: IGmxVirtualTokenResolver(exchangeRouterContractGuard)
      });
    }
    if (method == IGmxExchangeRouter.multicall.selector) {
      bytes[] memory multicallParams = abi.decode(params, (bytes[]));
      bytes memory lastCallData = multicallParams[multicallParams.length - 1];
      method = GmxHelperLib.getMethod(lastCallData);
      if (method == IGmxExchangeRouter.createDeposit.selector) {
        bytes32 key = contractGuardVars.dataStore.getCurrentKey();
        IGmxDeposit.Props memory latestDeposit = contractGuardVars.reader.getDeposit(contractGuardVars.dataStore, key);
        uint256 pendingDepositCount = contractGuardVars.dataStore.getAccountDepositCount(
          latestDeposit.addresses.account
        );
        require(pendingDepositCount == 1, "only one deposit allowed");
        require(latestDeposit.numbers.callbackGasLimit >= CALLBACK_GAS_LIMIT, "low callback gas limit");
        (uint256 inputTokensValueD18, uint256 outputTokensValueD18) = GmxHelperLib.getMaxDepositSlippageData({
          afterDepositData: GmxStructs.GmxAfterDepositData({
            account: latestDeposit.addresses.account,
            market: latestDeposit.addresses.market,
            initialLongToken: latestDeposit.addresses.initialLongToken,
            initialShortToken: latestDeposit.addresses.initialShortToken,
            initialLongTokenAmount: latestDeposit.numbers.initialLongTokenAmount,
            initialShortTokenAmount: latestDeposit.numbers.initialShortTokenAmount,
            minMarketTokens: latestDeposit.numbers.minMarketTokens
          }),
          priceDependencies: priceDependencies,
          isMinOutputAmountUsed: true,
          optionalOutputAmount: 0
        });
        _checkSlippage(
          contractGuardVars.slippageAccumulator,
          poolManagerLogic,
          SlippageAccumulator.SwapData({
            srcAsset: latestDeposit.addresses.market, // using USDPriceAggregator
            dstAsset: latestDeposit.addresses.market, // using USDPriceAggregator
            srcAmount: inputTokensValueD18,
            dstAmount: outputTokensValueD18
          })
        );
      } else if (method == IGmxExchangeRouter.createWithdrawal.selector) {
        //
        bytes32 key = contractGuardVars.dataStore.getCurrentKey();
        IGmxWithdrawal.Props memory latestWithdrawal = contractGuardVars.reader.getWithdrawal(
          contractGuardVars.dataStore,
          key
        );
        uint256 pendingWithdrawalCount = contractGuardVars.dataStore.getAccountWithdrawalCount(
          latestWithdrawal.addresses.account
        );
        require(pendingWithdrawalCount == 1, "only one withdrawal allowed");
        require(latestWithdrawal.numbers.callbackGasLimit >= CALLBACK_GAS_LIMIT, "low callback gas limit");
        (uint256 inputTokensValue, uint256 outputTokensValue) = GmxHelperLib.getMaxWithdrawalSlippageData({
          afterWithdrawalData: GmxStructs.GmxAfterWithdrawalData({
            account: latestWithdrawal.addresses.account,
            market: latestWithdrawal.addresses.market,
            marketTokenAmount: latestWithdrawal.numbers.marketTokenAmount,
            minLongTokenAmount: latestWithdrawal.numbers.minLongTokenAmount,
            minShortTokenAmount: latestWithdrawal.numbers.minShortTokenAmount
          }),
          priceDependencies: priceDependencies,
          isMinOutputAmountUsed: true,
          optionalOutputLongTokenAmount: 0,
          optionalOutputShortTokenAmount: 0
        });
        _checkSlippage(
          contractGuardVars.slippageAccumulator,
          poolManagerLogic,
          SlippageAccumulator.SwapData({
            srcAsset: latestWithdrawal.addresses.market, // using USDPriceAggregator
            dstAsset: latestWithdrawal.addresses.market, // using USDPriceAggregator
            srcAmount: inputTokensValue,
            dstAmount: outputTokensValue
          })
        );
      } else if (method == IGmxExchangeRouter.createOrder.selector) {
        // preliminary length check and decoding CreateOrderParams
        GmxHelperLib.decodeCreateOrder(multicallParams);
        bytes32 key = contractGuardVars.dataStore.getCurrentKey();
        Order.Props memory latestOrder = contractGuardVars.reader.getOrder(contractGuardVars.dataStore, key);
        uint256 pendingOrderCount = contractGuardVars.dataStore.getAccountOrderCount(latestOrder.addresses.account);
        require(pendingOrderCount == 1, "only one order allowed"); // ensure leverage and slippage check only for the latest order
        require(latestOrder.numbers.callbackGasLimit >= CALLBACK_GAS_LIMIT, "low callback gas limit");
        if (latestOrder.numbers.orderType == Order.OrderType.MarketSwap) {
          (uint256 inputTokensValue, uint256 outputTokensValue) = GmxHelperLib.getMaxSwapSlippageData({
            afterSwapOrderData: GmxStructs.GmxAfterSwapOrderData({
              account: latestOrder.addresses.account,
              swapPath: latestOrder.addresses.swapPath,
              initialCollateralToken: latestOrder.addresses.initialCollateralToken,
              minOutputAmount: latestOrder.numbers.minOutputAmount,
              initialCollateralDeltaAmount: latestOrder.numbers.initialCollateralDeltaAmount
            }),
            priceDependencies: priceDependencies,
            isMinOutputAmountUsed: true,
            optionalOutputAmount: 0
          });
          _checkSlippage(
            contractGuardVars.slippageAccumulator,
            poolManagerLogic,
            SlippageAccumulator.SwapData({
              srcAsset: latestOrder.addresses.swapPath[0], // using USDPriceAggregator
              dstAsset: latestOrder.addresses.swapPath[0], // using USDPriceAggregator
              srcAmount: inputTokensValue,
              dstAmount: outputTokensValue
            })
          );
        } else {
          // for MarketIncrease or MarketDecrease
          maxLeverageCheck(latestOrder, priceDependencies, exchangeRouterContractGuard);
        }
      }
    } else if (method == IGmxExchangeRouter.claimCollateral.selector) {
      (address[] memory markets, address[] memory tokens, uint256[] memory timeKeys, address receiver) = abi.decode(
        params,
        (address[], address[], uint256[], address)
      );
      GmxHelperLib.accessControl(address(contractGuardVars.nftTracker.poolFactory()), poolManagerLogic);
      for (uint256 i; i < markets.length; ++i) {
        GmxClaimableCollateralTrackerLib.cleanUpClaimableCollateralTimeKey(
          address(contractGuardVars.nftTracker),
          address(contractGuardVars.dataStore),
          to,
          GmxClaimableCollateralTrackerLib.ClaimableCollateralParams({
            market: markets[i],
            token: tokens[i],
            timeKey: timeKeys[i],
            account: receiver
          })
        );
      }
    }
  }
}
