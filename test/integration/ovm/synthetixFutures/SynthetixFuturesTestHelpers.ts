import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { BigNumber } from "ethers";
import { ethers } from "hardhat";
import { Address } from "../../../../deployment/types";
import { IFuturesMarket__factory, PoolLogic, SynthetixFuturesMarketAssetGuard } from "../../../../types";
import { units } from "../../../testHelpers";
import { IDeployments } from "../../utils/deployContracts/deployContracts";
import { utils } from "../../utils/utils";
import { ChainDataOVM } from "../../../../config/chainData/chainDataTypes";

const iFuturesMarket = new ethers.utils.Interface(IFuturesMarket__factory.abi);

export type FuturesTestHelpers = typeof futuresTestHelpers;

export const futuresTestHelpers = {
  setup: async (deployments: IDeployments, ovmChainData: ChainDataOVM): Promise<SynthetixFuturesMarketAssetGuard> => {
    const governance = deployments.governance;
    const assetHandler = deployments.assetHandler;
    // N.B We use the sUSD Aggregator not USDAggregator, because futures value is calculated in sUSD
    await assetHandler.addAsset(
      ovmChainData.futures.ethMarket,
      101,
      await assetHandler.priceAggregators(ovmChainData.assets.susd),
    );

    const SynthetixFuturesMarketContractGuard = await ethers.getContractFactory("SynthetixFuturesMarketContractGuard");
    const futuresMarketContractGuard = await SynthetixFuturesMarketContractGuard.deploy();
    await futuresMarketContractGuard.deployed();

    await governance.setContractGuard(ovmChainData.futures.ethMarket, futuresMarketContractGuard.address);

    const SynthetixFuturesMarketAssetGuard = await ethers.getContractFactory("SynthetixFuturesMarketAssetGuard");
    const futuresMarketAssetGuard = await SynthetixFuturesMarketAssetGuard.deploy();
    await futuresMarketAssetGuard.deployed();

    await governance.setAssetGuard(101, futuresMarketAssetGuard.address);
    return futuresMarketAssetGuard;
  },

  calculateProfitLoss: async (options: {
    poolLogicProxy: PoolLogic;
    marketAddress: Address;
    manipulatePriceByPercent: number;
  }): Promise<BigNumber> => {
    const { poolLogicProxy, marketAddress, manipulatePriceByPercent } = options;
    const futuresMarket = await ethers.getContractAt("IFuturesMarket", marketAddress);
    const [, , , lastPrice, size] = await futuresMarket.positions(poolLogicProxy.address);
    const newPrice = lastPrice.add(lastPrice.mul(manipulatePriceByPercent).div(100));
    const priceShift = newPrice.sub(lastPrice);

    return size.mul(priceShift).div(units(1));
  },

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

    const futuresMarket = await ethers.getContractAt("IFuturesMarket", marketAddress);
    const [fee] = await futuresMarket.orderFee(size);
    const transferMargin = iFuturesMarket.encodeFunctionData("transferMargin", [margin]);
    const modifyPositionWithTracking = iFuturesMarket.encodeFunctionData("modifyPositionWithTracking", [
      size,
      ethers.utils.formatBytes32String("tracking"),
    ]);

    await poolLogicProxy.connect(poolManager).execTransaction(marketAddress, transferMargin);
    await poolLogicProxy.connect(poolManager).execTransaction(marketAddress, modifyPositionWithTracking);

    return fee;
  },
  close: async (options: { poolLogicProxy: PoolLogic; poolManager: SignerWithAddress; marketAddress: Address }) => {
    const { poolLogicProxy, poolManager, marketAddress } = options;
    const closePositionWithTracking = iFuturesMarket.encodeFunctionData("closePositionWithTracking", [
      ethers.utils.formatBytes32String("tracking"),
    ]);
    await poolLogicProxy.connect(poolManager).execTransaction(marketAddress, closePositionWithTracking);
  },
  closeOrLiquidateAndWithdrawMargin: async (options: {
    poolLogicProxy: PoolLogic;
    poolManager: SignerWithAddress;
    marketAddress: Address;
  }) => {
    const { poolLogicProxy, poolManager, marketAddress } = options;
    const futuresMarket = await ethers.getContractAt("IFuturesMarket", marketAddress);
    if (await futuresMarket.canLiquidate(poolLogicProxy.address)) {
      await futuresMarket.liquidatePosition(poolLogicProxy.address);
    } else {
      const closePositionWithTracking = iFuturesMarket.encodeFunctionData("closePositionWithTracking", [
        ethers.utils.formatBytes32String("tracking"),
      ]);
      const withdrawAllMargin = iFuturesMarket.encodeFunctionData("withdrawAllMargin");
      await poolLogicProxy.connect(poolManager).execTransaction(marketAddress, closePositionWithTracking);
      await poolLogicProxy.connect(poolManager).execTransaction(marketAddress, withdrawAllMargin);
    }
  },
  getCloseFee: async (options: { poolLogicProxy: PoolLogic; marketAddress: Address }): Promise<BigNumber> => {
    const { poolLogicProxy, marketAddress } = options;
    const futuresMarket = await ethers.getContractAt("IFuturesMarket", marketAddress);
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

    const futuresMarket = await ethers.getContractAt("IFuturesMarket", marketAddress);
    await futuresMarket.transferMargin(margin);
    await futuresMarket.modifyPosition(size);
    await futuresTestHelpers.manipulateChainLinkOracle(baseAssetOracleAddress, manipulateByPercent);
    await futuresMarket.closePosition();
    await futuresMarket.withdrawAllMargin();
  },
};
