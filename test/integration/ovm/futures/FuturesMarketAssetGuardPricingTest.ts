import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { BigNumber } from "ethers";
import { ethers } from "hardhat";
import { ovmChainData } from "../../../../config/chainData/ovm-data";
import {
  AssetHandler,
  FuturesMarketAssetGuard,
  ISynthAddressProxy,
  PoolFactory,
  PoolLogic,
  PoolManagerLogic,
} from "../../../../types";
import { units } from "../../../TestHelpers";
import { createFund } from "../../utils/createFund";
import { deployContracts, IDeployments } from "../../utils/deployContracts/deployContracts";
import { getAccountToken } from "../../utils/getAccountTokens";
import { utils } from "../../utils/utils";
import { futuresTestHelpers } from "./FuturesTestHelpers";
const { assets } = ovmChainData;

interface IBalanceTestCase {
  name: string;
  margin: BigNumber;
  leverage: number;
  isShort: boolean;
  manipulatePriceByPercent: number;
}

const sUSDProxy_target_tokenState = "0x92bac115d89ca17fd02ed9357ceca32842acb4c2";

describe("FuturesMarketAssetGuard Test", function () {
  let deployments: IDeployments;
  let susdProxy: ISynthAddressProxy, logicOwner: SignerWithAddress, manager: SignerWithAddress;
  let poolFactory: PoolFactory, poolLogicProxy: PoolLogic, poolManagerLogicProxy: PoolManagerLogic;
  const ETH_FUTURES_MARKET = ovmChainData.futures.ethMarket;
  const HUNDRED_SUSD = units(100);
  let assetHandler: AssetHandler;
  let futuresMarketAssetGuard: FuturesMarketAssetGuard;

  let snapId: string;

  after(async () => {
    await utils.evmRestoreSnap(snapId);
  });
  before(async function () {
    snapId = await utils.evmTakeSnap();
    [logicOwner, manager] = await ethers.getSigners();
    deployments = await deployContracts("ovm");

    poolFactory = deployments.poolFactory;
    assetHandler = deployments.assetHandler;

    futuresMarketAssetGuard = await futuresTestHelpers.setupFutures(deployments, ovmChainData);

    susdProxy = await ethers.getContractAt("ISynthAddressProxy", assets.susd);

    await getAccountToken(HUNDRED_SUSD, logicOwner.address, sUSDProxy_target_tokenState, 3);
    expect(await susdProxy.balanceOf(logicOwner.address)).to.equal(HUNDRED_SUSD);

    const fund = await createFund(
      poolFactory,
      logicOwner,
      manager,
      [
        { asset: assets.susd, isDeposit: true },
        { asset: ETH_FUTURES_MARKET, isDeposit: false },
      ],
      {
        performance: ethers.BigNumber.from("0"),
        management: ethers.BigNumber.from("0"),
      },
    );
    poolLogicProxy = fund.poolLogicProxy;
    poolManagerLogicProxy = fund.poolManagerLogicProxy;

    await susdProxy.approve(poolLogicProxy.address, HUNDRED_SUSD);
    await poolLogicProxy.deposit(assets.susd, HUNDRED_SUSD);
  });

  let beforeEachSnapId: string;

  afterEach(async () => {
    await utils.evmRestoreSnap(beforeEachSnapId);
  });

  beforeEach(async function () {
    beforeEachSnapId = await utils.evmTakeSnap();
  });

  describe("Create and Close Normal Future", () => {
    // This test creates, manipulates and closes a future as an EOA
    // And its job is to assert that the Synthetix Futures system is working as expected
    // Before we start testing as a pool
    it("Logic Owner can create and close future", async () => {
      await getAccountToken(HUNDRED_SUSD, logicOwner.address, sUSDProxy_target_tokenState, 3);
      await futuresTestHelpers.createFutureOwner({
        futuresMarketAddress: ETH_FUTURES_MARKET,
        baseAssetOracleAddress: await assetHandler.priceAggregators(assets.weth),
        margin: HUNDRED_SUSD,
        leverage: 1,
        isShort: false,
        baseAssetPrice: await assetHandler.getUSDPrice(assets.seth),
        manipulateByPercent: 100,
      });
    });
  });

  describe("getBalance", () => {
    it("Margin is included for closed positions", async () => {
      await futuresTestHelpers.createFuture({
        futuresMarketAddress: ETH_FUTURES_MARKET,
        poolLogicProxy: poolLogicProxy,
        poolManager: manager,
        margin: HUNDRED_SUSD,
        leverage: 1,
        isShort: false,
        baseAssetPrice: await assetHandler.getUSDPrice(assets.seth),
      });

      const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();
      await futuresTestHelpers.closeFuture({
        futuresMarketAddress: ETH_FUTURES_MARKET,
        poolLogicProxy: poolLogicProxy,
        poolManager: manager,
      });

      expect(await poolManagerLogicProxy.totalFundValue()).to.be.closeTo(
        totalFundValueBefore,
        totalFundValueBefore.div(1000),
      );
    });
    // Pool Exists with 100 sUSD in it. Then:
    // Creates future
    // Checks fundValue is correct
    // Manipulates future.baseAssetPrice
    // Checks fundValue is as expected (adjust for price manipulation)
    // Closes future
    // Checks fundValue is as above
    const balanceTest = (balanceTest: IBalanceTestCase) => {
      const { name, margin, leverage, isShort, manipulatePriceByPercent } = balanceTest;
      it(name, async () => {
        const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();
        const openFee = await futuresTestHelpers.createFuture({
          poolLogicProxy,
          poolManager: manager,
          futuresMarketAddress: ETH_FUTURES_MARKET,
          margin,
          leverage,
          isShort,
          baseAssetPrice: await assetHandler.getUSDPrice(assets.seth),
        });
        const futuresBalance = await futuresMarketAssetGuard.getBalance(poolLogicProxy.address, ETH_FUTURES_MARKET);
        const closeFee = await futuresTestHelpers.getCloseFee({
          poolLogicProxy,
          futuresMarketAddress: ETH_FUTURES_MARKET,
        });
        expect(futuresBalance).to.closeTo(HUNDRED_SUSD.sub(openFee).sub(closeFee), HUNDRED_SUSD.div(1000));
        const fundValueAfterFuturesPurchase = await poolManagerLogicProxy.totalFundValue();
        expect(fundValueAfterFuturesPurchase).to.be.closeTo(
          totalFundValueBefore.sub(openFee).sub(closeFee),
          totalFundValueBefore.div(1000),
        );

        ///
        /// We manipulate the chainLink price of the asset and check its reflected in the fundValue
        ///
        if (manipulatePriceByPercent != 0) {
          const expectedProfitSUSD = await futuresTestHelpers.calculateFuturesProfitLoss({
            poolLogicProxy,
            futuresMarketAddress: ETH_FUTURES_MARKET,
            manipulatePriceByPercent,
          });
          let expectedProfitUSD = await poolManagerLogicProxy["assetValue(address,uint256)"](
            assets.susd,
            // Can only pass unsigned int to assetValue
            expectedProfitSUSD.lt(0) ? expectedProfitSUSD.mul(-1) : expectedProfitSUSD,
          );
          // Switch back to signed int
          expectedProfitUSD = expectedProfitSUSD.lt(0) ? expectedProfitUSD.mul(-1) : expectedProfitUSD;

          let expectedFundValue = fundValueAfterFuturesPurchase.add(expectedProfitUSD);
          expectedFundValue = expectedFundValue.lt(0) ? BigNumber.from(0) : expectedFundValue;

          // Manipulate the baseAsset price
          await futuresTestHelpers.manipulateChainLinkOracle(
            await assetHandler.priceAggregators(assets.weth),
            manipulatePriceByPercent,
          );
          const fundValueAfterPriceManipulation = await poolManagerLogicProxy.totalFundValue();
          expect(fundValueAfterPriceManipulation).to.be.closeTo(expectedFundValue, expectedFundValue.div(100).mul(5));
        }
        const fundValueBeforeClose = await poolManagerLogicProxy.totalFundValue();

        await futuresTestHelpers.closeFutureOrLiquidateAndWithdrawMargin({
          poolLogicProxy,
          poolManager: manager,
          futuresMarketAddress: ETH_FUTURES_MARKET,
        });

        expect(await futuresMarketAssetGuard.getBalance(poolLogicProxy.address, ETH_FUTURES_MARKET)).to.equal(0);
        expect(await poolManagerLogicProxy["assetValue(address)"](ETH_FUTURES_MARKET)).to.equal(0);

        expect(await poolManagerLogicProxy.totalFundValue()).to.be.closeTo(
          fundValueBeforeClose,
          fundValueBeforeClose.div(100),
        );
      });
    };

    [
      {
        name: "Prices 1x long future correctly",
        margin: HUNDRED_SUSD,
        leverage: 1,
        isShort: false,
        manipulatePriceByPercent: 0,
      },
      {
        name: "Prices 1x isShort future correctly",
        margin: HUNDRED_SUSD,
        leverage: 1,
        isShort: true,
        manipulatePriceByPercent: 0,
      },
      {
        name: "Prices 10x long future correctly",
        margin: HUNDRED_SUSD,
        leverage: 10,
        isShort: false,
        manipulatePriceByPercent: 0,
      },
      {
        name: "Prices 10x isShort future correctly",
        margin: HUNDRED_SUSD,
        leverage: 10,
        isShort: true,
        manipulatePriceByPercent: 0,
      },
      {
        name: "Prices 1x long future correctly when baseAssetPrice Increases by 100%",
        margin: HUNDRED_SUSD,
        leverage: 1,
        isShort: false,
        manipulatePriceByPercent: 100,
      },
      {
        name: "Prices 10x long future correctly when baseAssetPrice Increases by 10%.",
        margin: HUNDRED_SUSD,
        leverage: 10,
        isShort: false,
        manipulatePriceByPercent: 10,
      },
      {
        name: "Prices 10x long future correctly when baseAssetPrice Increases by 100%",
        margin: HUNDRED_SUSD,
        leverage: 10,
        isShort: false,
        manipulatePriceByPercent: 100,
      },
      {
        name: "Prices 1x isShort future correctly when baseAssetPrice Increases by 100%",
        margin: HUNDRED_SUSD,
        leverage: 1,
        isShort: true,
        manipulatePriceByPercent: 100,
      },
      {
        name: "Prices 10x isShort future correctly when baseAssetPrice Increases by 100%",
        margin: HUNDRED_SUSD,
        leverage: 10,
        isShort: true,
        manipulatePriceByPercent: 10,
      },
      {
        name: "Prices 1x long future correctly when baseAssetPrice Decreases by 50%",
        margin: HUNDRED_SUSD,
        leverage: 1,
        isShort: false,
        manipulatePriceByPercent: -50,
      },
      {
        name: "Prices 10x long future correctly when baseAssetPrice Decreases by 50%",
        margin: HUNDRED_SUSD,
        leverage: 10,
        isShort: false,
        manipulatePriceByPercent: -50,
      },
      {
        name: "Prices 1x isShort future correctly when baseAssetPrice Decreases by 50%",
        margin: HUNDRED_SUSD,
        leverage: 1,
        isShort: true,
        manipulatePriceByPercent: -50,
      },
      {
        name: "Prices 10x isShort future correctly when baseAssetPrice Decreases by 50%",
        margin: HUNDRED_SUSD,
        leverage: 10,
        isShort: true,
        manipulatePriceByPercent: -50,
      },
    ].forEach(balanceTest);
  });
});
