import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { BigNumber } from "ethers";
import { ethers } from "hardhat";
import { assert } from "chai";
import { EvmPriceServiceConnection } from "@pythnetwork/pyth-evm-js";

import { Address } from "../../../../deployment/types";
import { IPerpsV2Market, PoolLogic, SynthetixPerpsV2MarketAssetGuard } from "../../../../types";
import { units, toBytes32 } from "../../../testHelpers";
import { IDeployments } from "../../utils/deployContracts/deployContracts";
import { utils } from "../../utils/utils";
import { ChainDataOVM } from "../../../../config/chainData/chainDataTypes";
import { AssetType } from "../../../../deployment/upgrade/jobs/assetsJob";
import { FuturesTestHelpers } from "../synthetixFutures/SynthetixFuturesTestHelpers";

const ORDER_FILL_PRICE = BigNumber.from("2000000000000000000000"); // $2k, but should get fill price instead

enum OrderType {
  Atomic,
  Delayed,
  Offchain,
}

type Position = {
  id: BigNumber;
  lastFundingIndex: BigNumber;
  margin: BigNumber;
  lastPrice: BigNumber;
  size: BigNumber;
};

type PerpsV2Helper = {
  setup: (
    deployments: IDeployments,
    ovmChainData: ChainDataOVM,
    whitelistedPools?: Address[],
  ) => Promise<SynthetixPerpsV2MarketAssetGuard>;
  createDelayedOrder: (options: {
    poolLogicProxy: PoolLogic;
    poolManager: SignerWithAddress;
    marketAddress: Address;
    margin: BigNumber;
    leverage: number;
    isShort: boolean;
    baseAssetPrice: BigNumber;
    skipOrderExecution?: boolean;
  }) => Promise<BigNumber>;
  executeOffchainDelayedOrder: (
    perpsV2Market: IPerpsV2Market | string,
    poolManager: SignerWithAddress,
    poolLogicProxy: PoolLogic,
  ) => Promise<void>;
  getPosition: (options: { poolLogicProxy: PoolLogic; marketAddress: Address }) => Promise<{
    id: BigNumber;
    lastFundingIndex: BigNumber;
    margin: BigNumber;
    lastPrice: BigNumber;
    size: BigNumber;
    leverage: BigNumber;
  }>;
  closeDelayedOrder: (options: {
    poolLogicProxy: PoolLogic;
    poolManager: SignerWithAddress;
    marketAddress: Address;
  }) => Promise<void>;
  getMinKeeperFee: (addressResolver: Address) => Promise<BigNumber>;
  increaseRealTime: (seconds: number) => Promise<void>;
  getFillPrice: (perpsV2Market: IPerpsV2Market, size: BigNumber) => Promise<BigNumber>;
};

export type PerpsV2TestHelpers = typeof perpsV2TestHelpers;

export const perpsV2TestHelpers: FuturesTestHelpers & PerpsV2Helper = {
  setup: async (
    deployments: IDeployments,
    ovmChainData: ChainDataOVM,
    whitelistedPools?: Address[],
  ): Promise<SynthetixPerpsV2MarketAssetGuard> => {
    const governance = deployments.governance;
    const assetHandler = deployments.assetHandler;
    // N.B We use the sUSD Aggregator not USDAggregator, because perpsV2 value is calculated in sUSD
    await assetHandler.addAsset(
      ovmChainData.perpsV2.ethMarket,
      AssetType["Synthetix PerpsV2 Market Asset"],
      await assetHandler.priceAggregators(ovmChainData.assets.susd),
    );

    const SynthetixPerpsV2MarketContractGuard = await ethers.getContractFactory("SynthetixPerpsV2MarketContractGuard");
    const perpsV2MarketContractGuard = await SynthetixPerpsV2MarketContractGuard.deploy(
      ovmChainData.assets.susd,
      whitelistedPools ? whitelistedPools : [],
    );
    await perpsV2MarketContractGuard.deployed();

    await governance.setContractGuard(ovmChainData.perpsV2.ethMarket, perpsV2MarketContractGuard.address);

    const SynthetixPerpsV2MarketAssetGuard = await ethers.getContractFactory("SynthetixPerpsV2MarketAssetGuard");
    const perpsV2MarketAssetGuard = await SynthetixPerpsV2MarketAssetGuard.deploy(
      ovmChainData.perpsV2.addressResolver,
      ovmChainData.assets.susd,
    );
    await perpsV2MarketAssetGuard.deployed();

    await governance.setAssetGuard(AssetType["Synthetix PerpsV2 Market Asset"], perpsV2MarketAssetGuard.address);
    return perpsV2MarketAssetGuard;
  },

  calculateProfitLoss: async (options: {
    poolLogicProxy: PoolLogic;
    marketAddress: Address;
    manipulatePriceByPercent: number;
  }): Promise<BigNumber> => {
    const { poolLogicProxy, marketAddress, manipulatePriceByPercent } = options;
    const perpsV2Market = await ethers.getContractAt("IPerpsV2Market", marketAddress);
    const [, , , lastPrice, size] = await perpsV2Market.positions(poolLogicProxy.address);
    const newPrice = lastPrice.add(lastPrice.mul(manipulatePriceByPercent).div(100));
    const priceShift = newPrice.sub(lastPrice);

    return size.mul(priceShift).div(units(1));
  },
  // Use createDelayedOrder as this type of order is no longer supported by Synthetix
  create: async (options: {
    poolLogicProxy: PoolLogic;
    poolManager: SignerWithAddress;
    marketAddress: Address;
    margin: BigNumber;
    leverage: number;
    isShort: boolean;
    baseAssetPrice: BigNumber;
  }): Promise<BigNumber> => {
    const { poolLogicProxy, poolManager, marketAddress, margin, leverage, isShort, baseAssetPrice } = options;
    // size = margin*10**18/assetPrice*leverage
    let size = margin.mul(units(1)).div(baseAssetPrice).mul(leverage);

    if (isShort) {
      size = size.mul(-1);
    }

    const perpsV2Market = await ethers.getContractAt("IPerpsV2Market", marketAddress);
    const [fee] = await perpsV2Market.orderFee(size, OrderType.Offchain);
    const transferMargin = (await perpsV2Market.populateTransaction.transferMargin(margin)).data;
    assert(transferMargin);

    const modifyPositionWithTracking = (
      await perpsV2Market.populateTransaction.modifyPositionWithTracking(
        size,
        ORDER_FILL_PRICE,
        ethers.utils.formatBytes32String("tracking"),
      )
    ).data;
    assert(modifyPositionWithTracking);

    await poolLogicProxy.connect(poolManager).execTransaction(marketAddress, transferMargin);
    await poolLogicProxy.connect(poolManager).execTransaction(marketAddress, modifyPositionWithTracking);

    return fee;
  },

  createDelayedOrder: async (options: {
    poolLogicProxy: PoolLogic;
    poolManager: SignerWithAddress;
    marketAddress: Address;
    margin: BigNumber;
    leverage: number;
    isShort: boolean;
    baseAssetPrice: BigNumber;
    skipOrderExecution?: boolean;
  }): Promise<BigNumber> => {
    const {
      poolLogicProxy,
      poolManager,
      marketAddress,
      margin,
      leverage,
      isShort,
      baseAssetPrice,
      skipOrderExecution,
    } = options;
    // size = margin*10**18/assetPrice*leverage
    let size = margin.mul(units(1)).div(baseAssetPrice).mul(leverage);

    if (isShort) {
      size = size.mul(-1);
    }

    const perpsV2Market = await ethers.getContractAt("IPerpsV2Market", marketAddress);
    const fillPrice = await perpsV2TestHelpers.getFillPrice(perpsV2Market, size);

    // Atomic and Delayed orders have been deprecated by Synthetix in https://sips.synthetix.io/sccp/sccp-295/
    // Only Offchain orders remain
    const [fee] = await perpsV2Market.orderFee(size, OrderType.Offchain);
    const transferMargin = (await perpsV2Market.populateTransaction.transferMargin(margin)).data;
    assert(transferMargin);

    const delayedOrder = (
      await perpsV2Market.populateTransaction.submitOffchainDelayedOrderWithTracking(
        size,
        fillPrice,
        ethers.utils.formatBytes32String("tracking"),
      )
    ).data;
    assert(delayedOrder);

    await poolLogicProxy.connect(poolManager).execTransaction(marketAddress, transferMargin);

    if (size.eq(0)) return fee; // don't submit order if no leverage

    await perpsV2TestHelpers.increaseRealTime(2); // 2 sec delay just to ensure the next block timestamp is higher

    await poolLogicProxy.connect(poolManager).execTransaction(marketAddress, delayedOrder);

    if (!skipOrderExecution) {
      await perpsV2TestHelpers.executeOffchainDelayedOrder(perpsV2Market, poolManager, poolLogicProxy);
    }

    return fee;
  },
  // Use closeDelayedOrder as this type of order is no longer supported by Synthetix
  close: async (options: { poolLogicProxy: PoolLogic; poolManager: SignerWithAddress; marketAddress: Address }) => {
    const { poolLogicProxy, poolManager, marketAddress } = options;

    const perpsV2Market = await ethers.getContractAt("IPerpsV2Market", marketAddress);
    const closePositionWithTracking = (
      await perpsV2Market.populateTransaction.closePositionWithTracking(
        ORDER_FILL_PRICE,
        ethers.utils.formatBytes32String("tracking"),
      )
    ).data;
    assert(closePositionWithTracking);

    await poolLogicProxy.connect(poolManager).execTransaction(marketAddress, closePositionWithTracking);
  },

  closeDelayedOrder: async (options: {
    poolLogicProxy: PoolLogic;
    poolManager: SignerWithAddress;
    marketAddress: Address;
  }) => {
    const { poolLogicProxy, poolManager, marketAddress } = options;

    const perpsV2Market = await ethers.getContractAt("IPerpsV2Market", marketAddress);
    let [, , , , size] = await perpsV2Market.positions(poolLogicProxy.address);
    size = size.mul(-1); // we want to close the position

    const fillPrice = await perpsV2TestHelpers.getFillPrice(perpsV2Market, size);

    // Atomic and Delayed orders have been deprecated by Synthetix in https://sips.synthetix.io/sccp/sccp-295/
    // Only Offchain orders remain

    const delayedOrder = (
      await perpsV2Market.populateTransaction.submitOffchainDelayedOrderWithTracking(
        size,
        fillPrice,
        ethers.utils.formatBytes32String("tracking"),
      )
    ).data;
    assert(delayedOrder);

    await perpsV2TestHelpers.increaseRealTime(2); // 2 sec delay just to ensure the next block timestamp is higher

    await poolLogicProxy.connect(poolManager).execTransaction(marketAddress, delayedOrder);

    await perpsV2TestHelpers.executeOffchainDelayedOrder(perpsV2Market, poolManager, poolLogicProxy);
  },

  closeOrLiquidateAndWithdrawMargin: async (options: {
    poolLogicProxy: PoolLogic;
    poolManager: SignerWithAddress;
    marketAddress: Address;
  }) => {
    const { poolLogicProxy, poolManager, marketAddress } = options;
    const perpsV2Market = await ethers.getContractAt("IPerpsV2Market", marketAddress);
    if (await perpsV2Market.canLiquidate(poolLogicProxy.address)) {
      await perpsV2Market.liquidatePosition(poolLogicProxy.address);
    } else {
      await perpsV2TestHelpers.closeDelayedOrder({ poolLogicProxy, poolManager, marketAddress });

      const withdrawAllMargin = (await perpsV2Market.populateTransaction.withdrawAllMargin()).data;
      assert(withdrawAllMargin);
      await poolLogicProxy.connect(poolManager).execTransaction(marketAddress, withdrawAllMargin);
    }
  },
  getCloseFee: async (options: { poolLogicProxy: PoolLogic; marketAddress: Address }): Promise<BigNumber> => {
    const { poolLogicProxy, marketAddress } = options;
    const perpsV2Market = await ethers.getContractAt("IPerpsV2Market", marketAddress);
    const [, , , , size] = await perpsV2Market.positions(poolLogicProxy.address);
    if (!size.eq(0)) {
      const [fee] = await perpsV2Market.orderFee(size.mul(-1), OrderType.Offchain);
      return fee;
    }
    return BigNumber.from(0);
  },
  manipulateChainLinkOracle: async (oracleAddress: string, manipulateByPercent: number) => {
    // Chainlink Oracles are like a proxy so the address never changes, they have an underlying aggregator
    // We switch this out to our HackerPriceAggregator to manipulate the price.
    // Synthetix check the roundId etc so we can't use the FixedPriceAggregator
    // You cannot call the child aggregator directly onchain because it has access control so no direct proxying.
    // We just take all the lastRoundData and pass it to our HackerPriceAggregator and change the price
    const chainlinkAggregator = await ethers.getContractAt("IAggregatorV3InterfaceWithOwner", oracleAddress);
    const owner = await utils.impersonateAccount(await chainlinkAggregator.owner());
    const [roundId, answer, startedAt, updatedAt, answeredInRound] = await chainlinkAggregator.latestRoundData();
    // if the manipulateByPercent is 10 we increase the current price by 10%
    // if the manipulateByPercent is -10 we decrease the current price by 10%
    const answerManipulated = answer.add(answer.mul(manipulateByPercent).div(100));
    const HackerPriceAggregator = await ethers.getContractFactory("HackerPriceAggregator");
    const fixedPriceAggregator = await HackerPriceAggregator.deploy(
      roundId,
      answerManipulated,
      startedAt,
      updatedAt,
      answeredInRound,
    );
    await fixedPriceAggregator.deployed();
    await chainlinkAggregator.connect(owner).proposeAggregator(fixedPriceAggregator.address);
    await chainlinkAggregator.connect(owner).confirmAggregator(fixedPriceAggregator.address);
    const [, answerChain] = await chainlinkAggregator.latestRoundData();
    // Assert our price hack has worked
    if (!answerChain.eq(answerManipulated)) {
      throw new Error("manipulateChainLinkOracle failed");
    }
  },
  // Can't use as closePosition is no longer supported by Synthetix
  createAsOwner: async (options: {
    marketAddress: Address;
    baseAssetOracleAddress: Address;
    margin: BigNumber;
    leverage: number;
    isShort: boolean;
    baseAssetPrice: BigNumber;
    manipulateByPercent: number;
  }) => {
    const { marketAddress, baseAssetOracleAddress, margin, leverage, isShort, baseAssetPrice, manipulateByPercent } =
      options;
    // size = margin*10**18/assetPrice*leverage
    let size = margin.mul(units(1)).div(baseAssetPrice).mul(leverage);

    if (isShort) {
      size = size.mul(-1);
    }

    const perpsV2Market = await ethers.getContractAt("IPerpsV2Market", marketAddress);
    await perpsV2Market.transferMargin(margin);
    await perpsV2Market.modifyPosition(size, ORDER_FILL_PRICE);
    await perpsV2TestHelpers.manipulateChainLinkOracle(baseAssetOracleAddress, manipulateByPercent);
    await perpsV2Market.closePosition(ORDER_FILL_PRICE);
    await perpsV2Market.withdrawAllMargin();
  },
  // Executes a delayed offchain order after being submitted. Uses the Pyth Network API
  executeOffchainDelayedOrder: async (
    perpsV2Market: IPerpsV2Market | string,
    poolManager: SignerWithAddress,
    poolLogicProxy: PoolLogic,
  ) => {
    if (typeof perpsV2Market == "string") {
      perpsV2Market = await ethers.getContractAt("IPerpsV2Market", perpsV2Market);
    }

    await new Promise((f) => setTimeout(f, 20000)); // 20 sec
    const timestamp = Number((Date.now() / 1000).toFixed(0));
    await ethers.provider.send("evm_mine", [timestamp]);

    const connection = new EvmPriceServiceConnection("https://xc-mainnet.pyth.network"); // See Price Service endpoints section below for other endpoints

    const priceIds = [
      // You can find the ids of prices at https://pyth.network/developers/price-feed-ids
      "0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace", // ETH/USD price id in EVM mainnet
    ];

    const priceUpdateData = await connection.getPriceFeedsUpdateData(priceIds);

    await perpsV2Market.connect(poolManager).executeOffchainDelayedOrder(poolLogicProxy.address, priceUpdateData, {
      value: 1,
    });
  },
  getPosition: async (options: { poolLogicProxy: PoolLogic; marketAddress: Address }) => {
    const { poolLogicProxy, marketAddress } = options;
    const perpsV2Market = await ethers.getContractAt("IPerpsV2Market", marketAddress);
    const positionData: Position = await perpsV2Market.positions(poolLogicProxy.address);
    const sizeAbs = positionData.size.gte(0) ? positionData.size : positionData.size.mul(-1);
    const sizeValue = sizeAbs.mul(positionData.lastPrice).div(units(1)); // note: the price may vary because it's been updated by the offchain oracle
    const leverage = sizeValue.mul(units(1)).div(positionData.margin);
    const position = {
      id: positionData[0],
      lastFundingIndex: positionData[1],
      margin: positionData[2],
      lastPrice: positionData[3],
      size: positionData[4],
      leverage,
    };
    return position;
  },
  getMinKeeperFee: async (addressResolver: Address) => {
    const addressResolverContract = await ethers.getContractAt("IAddressResolver", addressResolver);
    const perpsV2MarketSettingsAddress = await addressResolverContract.getAddress(toBytes32("PerpsV2MarketSettings"));
    const perpsV2MarketSettings = await ethers.getContractAt("IPerpsV2MarketSettings", perpsV2MarketSettingsAddress);

    const keeperFee = await perpsV2MarketSettings.minKeeperFee();
    return keeperFee;
  },
  increaseRealTime: async (seconds: number) => {
    // Increases real time which can be used to make sure new block timestamps are higher
    // and that the Pyth oracle API calls are not stale
    await new Promise((f) => setTimeout(f, seconds * 1000));
    const timestamp = Number((Date.now() / 1000).toFixed(0));
    await ethers.provider.send("evm_mine", [timestamp]);
  },
  getFillPrice: async (perpsV2Market: IPerpsV2Market, size: BigNumber) => {
    let fillPrice = (await perpsV2Market.fillPrice(size)).price;
    if (size.gt(0)) {
      // opening long / closing short
      fillPrice = fillPrice.mul(101).div(100); // add 1% slippage on the fill
    } else {
      // opening short / closing long
      fillPrice = fillPrice.mul(99).div(100); // add 1% slippage on the fill
    }
    return fillPrice;
  },
};
