// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {Order} from "../../interfaces/gmx/IGmxOrder.sol";
import {IGmxDataStore} from "../../interfaces/gmx/IGmxDataStore.sol";
import {IGmxRoleStore} from "../../interfaces/gmx/IGmxRoleStore.sol";
import {IGmxReader} from "../../interfaces/gmx/IGmxReader.sol";
import {IGmxMarket} from "../../interfaces/gmx/IGmxMarket.sol";
import {GmxClaimableCollateralTrackerLib} from "./GmxClaimableCollateralTrackerLib.sol";
import {DhedgeNftTrackerStorage} from "../../utils/tracker/DhedgeNftTrackerStorage.sol";
import {IGmxEvent} from "../../interfaces/gmx/IGmxEvent.sol";
import {GmxAfterTxValidatorLib} from "./GmxAfterTxValidatorLib.sol";
import {GmxPriceLib} from "./GmxPriceLib.sol";
import {SlippageAccumulator} from "../../utils/SlippageAccumulator.sol";
import {IGmxExchangeRouterContractGuard} from "../../interfaces/gmx/IGmxExchangeRouterContractGuard.sol";
import {IPoolLogic} from "../../interfaces/IPoolLogic.sol";
import {GmxStructs} from "./GmxStructs.sol";
import {IGmxDeposit} from "../../interfaces/gmx/IGmxDeposit.sol";
import {IGmxWithdrawal} from "../../interfaces/gmx/IGmxWithdrawal.sol";
import {IGmxVirtualTokenResolver} from "../../interfaces/gmx/IGmxVirtualTokenResolver.sol";

library GmxAfterExcutionLib {
  bytes32 public constant CONTROLLER_ROLE_STORE_KEY = keccak256(abi.encode("CONTROLLER"));
  // @dev key for claimable collateral time divisor
  bytes32 public constant CLAIMABLE_COLLATERAL_TIME_DIVISOR =
    keccak256(abi.encode("CLAIMABLE_COLLATERAL_TIME_DIVISOR"));
  function trackClaimableCollateralAfterOrderExecution(
    DhedgeNftTrackerStorage nftTracker,
    Order.Props memory order,
    address guardedContract,
    address exchangeRouterContractGuard
  ) internal {
    IGmxDataStore dataStore = IGmxExchangeRouterContractGuard(exchangeRouterContractGuard).dataStore();
    IGmxReader reader = IGmxExchangeRouterContractGuard(exchangeRouterContractGuard).reader();
    require(
      IGmxRoleStore(dataStore.roleStore()).hasRole({account: msg.sender, roleKey: CONTROLLER_ROLE_STORE_KEY}),
      "invalid handler"
    );

    // Duplicate GMX time key calculation logic.
    // https://github.com/gmx-io/gmx-synthetics/blob/5173cbeb196ed5596373acd71c75a5c7a60a98f5/contracts/market/MarketUtils.sol#L541
    uint256 timeKey = block.timestamp / dataStore.getUint(CLAIMABLE_COLLATERAL_TIME_DIVISOR);
    IGmxMarket.Props memory market = reader.getMarket({_dataStore: dataStore, _market: order.addresses.market});

    handleClaimableCollateral({
      nftTracker: nftTracker,
      guardedContract: guardedContract,
      dataStore: dataStore,
      pool: order.addresses.account,
      market: order.addresses.market,
      token: market.longToken,
      timeKey: timeKey
    });

    // Some GMX markets have identical long and short tokens. In that case, we need to avoid adding the same claimable collateral twice.
    if (market.longToken != market.shortToken) {
      handleClaimableCollateral({
        nftTracker: nftTracker,
        guardedContract: guardedContract,
        dataStore: dataStore,
        pool: order.addresses.account,
        market: order.addresses.market,
        token: market.shortToken,
        timeKey: timeKey
      });
    }
  }

  function handleClaimableCollateral(
    DhedgeNftTrackerStorage nftTracker,
    address guardedContract,
    IGmxDataStore dataStore,
    address pool,
    address market,
    address token,
    uint256 timeKey
  ) internal {
    uint256 claimableCollateralAmount = dataStore.getUint(
      GmxClaimableCollateralTrackerLib.claimableCollateralAmountKey(
        GmxClaimableCollateralTrackerLib.ClaimableCollateralParams({
          market: market,
          token: token,
          timeKey: timeKey,
          account: pool
        })
      )
    );
    // if the negative impact threshold wasn't exceeded, we don't need to track the claimable collateral
    if (claimableCollateralAmount != 0) {
      GmxClaimableCollateralTrackerLib.addClaimableCollateralTimeKey({
        nftTracker: address(nftTracker),
        guardedContract: guardedContract,
        pool: pool,
        market: market,
        token: token,
        timeKey: timeKey
      });
    }
  }

  function afterOrderExecutionCallback(
    Order.Props memory order,
    address to,
    IGmxEvent.EventLogData memory eventData,
    address exchangeRouterContractGuard
  ) external {
    if (order.numbers.orderType == Order.OrderType.MarketDecrease) {
      DhedgeNftTrackerStorage nftTracker = IGmxExchangeRouterContractGuard(exchangeRouterContractGuard).nftTracker();
      GmxAfterExcutionLib.trackClaimableCollateralAfterOrderExecution({
        nftTracker: nftTracker,
        order: order,
        guardedContract: to,
        exchangeRouterContractGuard: address(this)
      });
    } else if (order.numbers.orderType == Order.OrderType.MarketSwap) {
      GmxAfterExcutionLib.afterSwapOrderExecutionCallback({
        order: order,
        to: to,
        eventData: eventData,
        exchangeRouterContractGuard: address(this)
      });
    }
  }

  function afterSwapOrderExecutionCallback(
    Order.Props memory order,
    address to,
    IGmxEvent.EventLogData memory eventData,
    address exchangeRouterContractGuard
  ) internal {
    GmxPriceLib.GmxPriceDependecies memory priceDeps;
    IGmxDataStore dataStore = IGmxExchangeRouterContractGuard(exchangeRouterContractGuard).dataStore();
    SlippageAccumulator slippageAccumulator;
    address poolManagerLogic;
    {
      require(
        IGmxRoleStore(dataStore.roleStore()).hasRole({account: msg.sender, roleKey: CONTROLLER_ROLE_STORE_KEY}),
        "invalid handler" // make sure it's called by the gmx permissioned keepers
      );
      GmxStructs.PoolSetting memory poolSetting = IGmxExchangeRouterContractGuard(exchangeRouterContractGuard)
        .dHedgePoolsWhitelist(order.addresses.account);
      require(poolSetting.poolLogic == order.addresses.account, "not gmx whitelisted");
      poolManagerLogic = IPoolLogic(poolSetting.poolLogic).poolManagerLogic();
      slippageAccumulator = IGmxExchangeRouterContractGuard(exchangeRouterContractGuard).slippageAccumulator();
      priceDeps = GmxPriceLib.GmxPriceDependecies({
        dataStore: dataStore,
        reader: IGmxExchangeRouterContractGuard(exchangeRouterContractGuard).reader(),
        assetHandler: GmxAfterTxValidatorLib.getAssetHandler(poolManagerLogic),
        virtualTokenResolver: IGmxVirtualTokenResolver(exchangeRouterContractGuard)
      });
    }

    (uint256 inputTokensValue, uint256 outputTokensValue) = GmxAfterTxValidatorLib.getMaxSwapSlippageData(
      order,
      priceDeps,
      false,
      // https://github.com/gmx-io/gmx-synthetics/blob/main/contracts/order/SwapOrderUtils.sol#L78
      eventData.uintItems.items[0].value
    );
    slippageAccumulator.updateSlippageImpact(
      poolManagerLogic,
      to,
      SlippageAccumulator.SwapData({
        srcAsset: order.addresses.swapPath[0], // using USDPriceAggregator
        dstAsset: order.addresses.swapPath[0], // using USDPriceAggregator
        srcAmount: inputTokensValue,
        dstAmount: outputTokensValue
      })
    );
  }

  function afterDepositExecutionCallback(
    IGmxDeposit.Props memory deposit,
    address to,
    IGmxEvent.EventLogData memory eventData,
    address exchangeRouterContractGuard
  ) external {
    GmxPriceLib.GmxPriceDependecies memory priceDeps;
    IGmxDataStore dataStore = IGmxExchangeRouterContractGuard(exchangeRouterContractGuard).dataStore();
    SlippageAccumulator slippageAccumulator;
    address poolManagerLogic;
    {
      dataStore = IGmxExchangeRouterContractGuard(exchangeRouterContractGuard).dataStore();
      require(
        IGmxRoleStore(dataStore.roleStore()).hasRole({account: msg.sender, roleKey: CONTROLLER_ROLE_STORE_KEY}),
        "invalid handler"
      );
      GmxStructs.PoolSetting memory poolSetting = IGmxExchangeRouterContractGuard(exchangeRouterContractGuard)
        .dHedgePoolsWhitelist(deposit.addresses.account);
      require(poolSetting.poolLogic == deposit.addresses.account, "not gmx whitelisted");
      poolManagerLogic = IPoolLogic(poolSetting.poolLogic).poolManagerLogic();
      slippageAccumulator = IGmxExchangeRouterContractGuard(exchangeRouterContractGuard).slippageAccumulator();
      priceDeps = GmxPriceLib.GmxPriceDependecies({
        dataStore: dataStore,
        reader: IGmxExchangeRouterContractGuard(exchangeRouterContractGuard).reader(),
        assetHandler: GmxAfterTxValidatorLib.getAssetHandler(poolManagerLogic),
        virtualTokenResolver: IGmxVirtualTokenResolver(exchangeRouterContractGuard)
      });
    }
    (uint256 inputTokensValue, uint256 outputTokensValue) = GmxAfterTxValidatorLib.getMaxDepositSlippageData({
      latestDeposit: deposit,
      priceDependencies: priceDeps,
      isMinOutputAmountUsed: false,
      // https://github.com/gmx-io/gmx-synthetics/blob/main/contracts/deposit/ExecuteDepositUtils.sol#L279
      optionalOutputAmount: eventData.uintItems.items[0].value
    });
    slippageAccumulator.updateSlippageImpact(
      poolManagerLogic,
      to,
      SlippageAccumulator.SwapData({
        srcAsset: deposit.addresses.market, // using USDPriceAggregator
        dstAsset: deposit.addresses.market, // using USDPriceAggregator
        srcAmount: inputTokensValue,
        dstAmount: outputTokensValue
      })
    );
  }

  function afterWithdrawalExecutionCallback(
    IGmxWithdrawal.Props memory withdrawal,
    address to,
    IGmxEvent.EventLogData memory eventData,
    address exchangeRouterContractGuard
  ) external {
    GmxPriceLib.GmxPriceDependecies memory priceDeps;
    IGmxDataStore dataStore = IGmxExchangeRouterContractGuard(exchangeRouterContractGuard).dataStore();
    SlippageAccumulator slippageAccumulator;
    address poolManagerLogic;
    {
      dataStore = IGmxExchangeRouterContractGuard(exchangeRouterContractGuard).dataStore();
      require(
        IGmxRoleStore(dataStore.roleStore()).hasRole({account: msg.sender, roleKey: CONTROLLER_ROLE_STORE_KEY}),
        "invalid handler"
      );
      GmxStructs.PoolSetting memory poolSetting = IGmxExchangeRouterContractGuard(exchangeRouterContractGuard)
        .dHedgePoolsWhitelist(withdrawal.addresses.account);
      require(poolSetting.poolLogic == withdrawal.addresses.account, "not gmx whitelisted");
      poolManagerLogic = IPoolLogic(poolSetting.poolLogic).poolManagerLogic();
      slippageAccumulator = IGmxExchangeRouterContractGuard(exchangeRouterContractGuard).slippageAccumulator();
      priceDeps = GmxPriceLib.GmxPriceDependecies({
        dataStore: dataStore,
        reader: IGmxExchangeRouterContractGuard(exchangeRouterContractGuard).reader(),
        assetHandler: GmxAfterTxValidatorLib.getAssetHandler(poolManagerLogic),
        virtualTokenResolver: IGmxVirtualTokenResolver(exchangeRouterContractGuard)
      });
    }
    uint256 inputTokensValue;
    uint256 outputTokensValue;
    {
      // https://github.com/gmx-io/gmx-synthetics/blob/main/contracts/withdrawal/ExecuteWithdrawalUtils.sol#L148
      uint256 outputAmount = eventData.uintItems.items[0].value; // longToken
      uint256 secondaryOutputAmount = eventData.uintItems.items[1].value; // shortToken
      (inputTokensValue, outputTokensValue) = GmxAfterTxValidatorLib.getMaxWithdrawalSlippageData({
        latestWithdrawal: withdrawal,
        priceDependencies: priceDeps,
        isMinOutputAmountUsed: false,
        optionalOutputLongTokenAmount: outputAmount,
        optionalOutputShortTokenAmount: secondaryOutputAmount
      });
    }

    slippageAccumulator.updateSlippageImpact(
      poolManagerLogic,
      to,
      SlippageAccumulator.SwapData({
        srcAsset: withdrawal.addresses.market, // using USDPriceAggregator
        dstAsset: withdrawal.addresses.market, // using USDPriceAggregator
        srcAmount: inputTokensValue,
        dstAmount: outputTokensValue
      })
    );
  }
}
