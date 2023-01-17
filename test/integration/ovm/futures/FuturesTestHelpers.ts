import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { BigNumber } from "ethers";
import { ethers } from "hardhat";
import { Address } from "../../../../deployment-scripts/types";
import { IFuturesMarket__factory, PoolLogic, FuturesMarketAssetGuard } from "../../../../types";
import { units } from "../../../TestHelpers";
import { IDeployments } from "../../utils/deployContracts/deployContracts";
import { utils } from "../../utils/utils";
import { ChainDataOVM } from "../../../../config/chainData/ChainDataType";

const iFuturesMarket = new ethers.utils.Interface(IFuturesMarket__factory.abi);

export const futuresTestHelpers = {
  setupFutures: async (deployments: IDeployments, ovmChainData: ChainDataOVM): Promise<FuturesMarketAssetGuard> => {
    const governance = deployments.governance;
    const assetHandler = deployments.assetHandler;
    // N.B We use the sUSD Aggregator not USDAggregator, because futures value is calculated in sUSD
    assetHandler.addAsset(
      ovmChainData.futures.ethMarket,
      101,
      await assetHandler.priceAggregators(ovmChainData.assets.susd),
    );

    const FuturesMarketContractGuard = await ethers.getContractFactory("FuturesMarketContractGuard");
    const futuresMarketContractGuard = await FuturesMarketContractGuard.deploy();
    await futuresMarketContractGuard.deployed();

    await governance.setContractGuard(ovmChainData.futures.ethMarket, futuresMarketContractGuard.address);

    const FuturesMarketAssetGuard = await ethers.getContractFactory("FuturesMarketAssetGuard");
    const futuresMarketAssetGuard = await FuturesMarketAssetGuard.deploy();
    await futuresMarketAssetGuard.deployed();

    await governance.setAssetGuard(101, futuresMarketAssetGuard.address);
    return futuresMarketAssetGuard;
  },

  calculateFuturesProfitLoss: async (options: {
    poolLogicProxy: PoolLogic;
    futuresMarketAddress: Address;
    manipulatePriceByPercent: number;
  }): Promise<BigNumber> => {
    const { poolLogicProxy, futuresMarketAddress, manipulatePriceByPercent } = options;
    const futuresMarket = await ethers.getContractAt("IFuturesMarket", futuresMarketAddress);
    const [, , , lastPrice, size] = await futuresMarket.positions(poolLogicProxy.address);
    const newPrice = lastPrice.add(lastPrice.mul(manipulatePriceByPercent).div(100));
    const priceShift = newPrice.sub(lastPrice);

    return size.mul(priceShift).div(units(1));
  },

  createFuture: async (options: {
    poolLogicProxy: PoolLogic;
    poolManager: SignerWithAddress;
    futuresMarketAddress: Address;
    margin: BigNumber;
    leverage: number;
    isShort: boolean;
    baseAssetPrice: BigNumber;
  }): Promise<BigNumber> => {
    const { poolLogicProxy, poolManager, futuresMarketAddress, margin, leverage, isShort, baseAssetPrice } = options;
    // size = margin*10**18/assetPrice*leverage
    let size = margin.mul(units(1)).div(baseAssetPrice).mul(leverage);

    if (isShort) {
      size = size.mul(-1);
    }

    const futuresMarket = await ethers.getContractAt("IFuturesMarket", futuresMarketAddress);
    const [fee] = await futuresMarket.orderFee(size);
    const transferMargin = iFuturesMarket.encodeFunctionData("transferMargin", [margin]);
    const modifyPositionWithTracking = iFuturesMarket.encodeFunctionData("modifyPositionWithTracking", [
      size,
      ethers.utils.formatBytes32String("tracking"),
    ]);

    await poolLogicProxy.connect(poolManager).execTransaction(futuresMarketAddress, transferMargin);
    await poolLogicProxy.connect(poolManager).execTransaction(futuresMarketAddress, modifyPositionWithTracking);

    return fee;
  },
  closeFuture: async (options: {
    poolLogicProxy: PoolLogic;
    poolManager: SignerWithAddress;
    futuresMarketAddress: Address;
  }) => {
    const { poolLogicProxy, poolManager, futuresMarketAddress } = options;
    const closePositionWithTracking = iFuturesMarket.encodeFunctionData("closePositionWithTracking", [
      ethers.utils.formatBytes32String("tracking"),
    ]);
    await poolLogicProxy.connect(poolManager).execTransaction(futuresMarketAddress, closePositionWithTracking);
  },
  closeFutureOrLiquidateAndWithdrawMargin: async (options: {
    poolLogicProxy: PoolLogic;
    poolManager: SignerWithAddress;
    futuresMarketAddress: Address;
  }) => {
    const { poolLogicProxy, poolManager, futuresMarketAddress } = options;
    const futuresMarket = await ethers.getContractAt("IFuturesMarket", futuresMarketAddress);
    if (await futuresMarket.canLiquidate(poolLogicProxy.address)) {
      await futuresMarket.liquidatePosition(poolLogicProxy.address);
    } else {
      const closePositionWithTracking = iFuturesMarket.encodeFunctionData("closePositionWithTracking", [
        ethers.utils.formatBytes32String("tracking"),
      ]);
      const withdrawAllMargin = iFuturesMarket.encodeFunctionData("withdrawAllMargin");
      await poolLogicProxy.connect(poolManager).execTransaction(futuresMarketAddress, closePositionWithTracking);
      await poolLogicProxy.connect(poolManager).execTransaction(futuresMarketAddress, withdrawAllMargin);
    }
  },
  getCloseFee: async (options: { poolLogicProxy: PoolLogic; futuresMarketAddress: Address }): Promise<BigNumber> => {
    const { poolLogicProxy, futuresMarketAddress } = options;
    const futuresMarket = await ethers.getContractAt("IFuturesMarket", futuresMarketAddress);
    const [, , , , size] = await futuresMarket.positions(poolLogicProxy.address);
    if (!size.eq(0)) {
      const [fee] = await futuresMarket.orderFee(size.mul(-1));
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
  createFutureOwner: async (options: {
    futuresMarketAddress: Address;
    baseAssetOracleAddress: Address;
    margin: BigNumber;
    leverage: number;
    isShort: boolean;
    baseAssetPrice: BigNumber;
    manipulateByPercent: number;
  }) => {
    const {
      futuresMarketAddress,
      baseAssetOracleAddress,
      margin,
      leverage,
      isShort,
      baseAssetPrice,
      manipulateByPercent,
    } = options;
    // size = margin*10**18/assetPrice*leverage
    let size = margin.mul(units(1)).div(baseAssetPrice).mul(leverage);

    if (isShort) {
      size = size.mul(-1);
    }

    const futuresMarket = await ethers.getContractAt("IFuturesMarket", futuresMarketAddress);
    await futuresMarket.transferMargin(margin);
    await futuresMarket.modifyPosition(size);
    await futuresTestHelpers.manipulateChainLinkOracle(baseAssetOracleAddress, manipulateByPercent);
    await futuresMarket.closePosition();
    await futuresMarket.withdrawAllMargin();
  },
};
