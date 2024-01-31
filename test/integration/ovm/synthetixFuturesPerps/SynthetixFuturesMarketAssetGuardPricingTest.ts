import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { BigNumber } from "ethers";
import { ethers } from "hardhat";
import { ovmChainData } from "../../../../config/chainData/ovmData";
import {
  AssetHandler,
  SynthetixFuturesMarketAssetGuard,
  ISynthAddressProxy,
  SynthetixPerpsV2MarketAssetGuard,
  PoolFactory,
  PoolLogic,
  PoolManagerLogic,
} from "../../../../types";
import { units } from "../../../testHelpers";
import { createFund } from "../../utils/createFund";
import { deployContracts, IDeployments } from "../../utils/deployContracts/deployContracts";
import { getAccountToken } from "../../utils/getAccountTokens";
import { utils } from "../../utils/utils";
import { PerpsV2TestHelpers } from "../synthetixPerpsV2/SynthetixPerpsV2TestHelpers";
const { assets } = ovmChainData;

interface IBalanceTestCase {
  name: string;
  margin: BigNumber;
  leverage: number;
  isShort: boolean;
  manipulatePriceByPercent: number;
}

export const CreateSynthetixFuturesMarketAssetGuardPricingTests = (
  testHelpers: PerpsV2TestHelpers,
  config: { ethMarket: string },
) => {
  describe("AssetGuard Pricing Tests", function () {
    let deployments: IDeployments;
    let susdProxy: ISynthAddressProxy, logicOwner: SignerWithAddress, manager: SignerWithAddress;
    let poolFactory: PoolFactory, poolLogicProxy: PoolLogic, poolManagerLogicProxy: PoolManagerLogic;
    const ETH_FUTURES_MARKET = config.ethMarket;
    const ONE_THOUSAND = units(1000);
    let assetHandler: AssetHandler;
    let marketAssetGuard: SynthetixFuturesMarketAssetGuard | SynthetixPerpsV2MarketAssetGuard;

    utils.beforeAfterReset(before, after);
    utils.beforeAfterReset(beforeEach, afterEach);

    before(async () => {
      [logicOwner, manager] = await ethers.getSigners();
      deployments = await deployContracts("ovm");

      poolFactory = deployments.poolFactory;
      assetHandler = deployments.assetHandler;

      susdProxy = await ethers.getContractAt("ISynthAddressProxy", assets.susd);

      await getAccountToken(ONE_THOUSAND, logicOwner.address, ovmChainData.synthetix.sUSDProxy_target_tokenState, 3);
      expect(await susdProxy.balanceOf(logicOwner.address)).to.equal(ONE_THOUSAND);

      const fund = await createFund(poolFactory, logicOwner, manager, [{ asset: assets.susd, isDeposit: true }], {
        performance: ethers.BigNumber.from("0"),
        management: ethers.BigNumber.from("0"),
      });
      poolLogicProxy = fund.poolLogicProxy;
      poolManagerLogicProxy = fund.poolManagerLogicProxy;

      // Deploy the Perps guards with the new fund whitelisted for use
      marketAssetGuard = await testHelpers.setup(deployments, ovmChainData, [fund.poolLogicProxy.address]);
      // Enable perps in the pool
      await fund.poolManagerLogicProxy
        .connect(manager)
        .changeAssets([{ asset: ETH_FUTURES_MARKET, isDeposit: false }], []);

      await susdProxy.approve(poolLogicProxy.address, ONE_THOUSAND);
      await poolLogicProxy.deposit(assets.susd, ONE_THOUSAND);
    });

    // Skip because only delayed offchain orders are now supported by Perps v2
    // Any issues will get picked up in later tests anyway
    describe.skip("Create and Close Normal Future", () => {
      // This test creates, manipulates and closes a future as an EOA
      // And its job is to assert that the Synthetix Futures system is working as expected
      // Before we start testing as a pool
      it("Logic Owner can create and close future", async () => {
        await getAccountToken(ONE_THOUSAND, logicOwner.address, ovmChainData.synthetix.sUSDProxy_target_tokenState, 3);
        await testHelpers.createAsOwner({
          marketAddress: ETH_FUTURES_MARKET,
          baseAssetOracleAddress: await assetHandler.priceAggregators(assets.weth),
          margin: ONE_THOUSAND,
          leverage: 1,
          isShort: false,
          baseAssetPrice: await assetHandler.getUSDPrice(assets.seth),
          manipulateByPercent: 100,
        });
      });
    });

    describe("Balance tests", () => {
      it("Perps trading blocked on a pool that is not whitelisted", async () => {
        await getAccountToken(ONE_THOUSAND, logicOwner.address, ovmChainData.synthetix.sUSDProxy_target_tokenState, 3);

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
        const poolLogicProxy2 = fund.poolLogicProxy;

        await susdProxy.approve(poolLogicProxy2.address, ONE_THOUSAND);
        await poolLogicProxy2.deposit(assets.susd, ONE_THOUSAND);

        await expect(
          testHelpers.createDelayedOrder({
            poolLogicProxy: poolLogicProxy2,
            poolManager: manager,
            marketAddress: ETH_FUTURES_MARKET,
            margin: ONE_THOUSAND,
            leverage: 1,
            isShort: false,
            baseAssetPrice: await assetHandler.getUSDPrice(assets.seth),
          }),
        ).to.be.revertedWith("pool not whitelisted for perps");
      });

      it("Margin is included for closed positions", async () => {
        await testHelpers.createDelayedOrder({
          marketAddress: ETH_FUTURES_MARKET,
          poolLogicProxy: poolLogicProxy,
          poolManager: manager,
          margin: ONE_THOUSAND,
          leverage: 1,
          isShort: false,
          baseAssetPrice: await assetHandler.getUSDPrice(assets.seth),
        });

        const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();
        const keeperFee = await testHelpers.getMinKeeperFee(ovmChainData.perpsV2.addressResolver);
        await testHelpers.closeDelayedOrder({
          marketAddress: ETH_FUTURES_MARKET,
          poolLogicProxy: poolLogicProxy,
          poolManager: manager,
        });
        // Fund value should be close to the value before, even with the fees
        const totalFundValueAfter = await poolManagerLogicProxy.totalFundValue();
        expect(totalFundValueAfter).to.be.closeTo(totalFundValueBefore.sub(keeperFee), totalFundValueBefore.div(500)); // within 0.5% due to Chainlink pricing vs Pyth oracle pricing
      });
      // Pool Exists with 1000 sUSD in it. Then:
      // Creates future
      // Checks fundValue is correct
      // Manipulates future.baseAssetPrice
      // Checks fundValue is as expected (adjust for price manipulation)
      // Closes future
      // Checks fundValue is as above
      const balanceTest = (balanceTest: IBalanceTestCase) => {
        const { name, margin, leverage, isShort, manipulatePriceByPercent } = balanceTest;
        it(name, async () => {
          // We only support leverage up to 2.5x
          if (leverage > 2.5) {
            await expect(
              testHelpers.createDelayedOrder({
                poolLogicProxy,
                poolManager: manager,
                marketAddress: ETH_FUTURES_MARKET,
                margin,
                leverage,
                isShort,
                baseAssetPrice: await assetHandler.getUSDPrice(assets.seth),
              }),
            ).to.be.revertedWith("leverage must be less than 2.5x");
            return;
          }

          const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();
          const keeperFee = await testHelpers.getMinKeeperFee(ovmChainData.perpsV2.addressResolver);
          const openFee = await testHelpers.createDelayedOrder({
            poolLogicProxy,
            poolManager: manager,
            marketAddress: ETH_FUTURES_MARKET,
            margin,
            leverage,
            isShort,
            baseAssetPrice: await assetHandler.getUSDPrice(assets.seth),
          });
          // Check that the perp position is open
          const futuresBalance = await marketAssetGuard.getBalance(poolLogicProxy.address, ETH_FUTURES_MARKET);
          expect(futuresBalance).to.be.gt(ONE_THOUSAND.mul(99).div(100).sub(keeperFee));
          const fundValueAfterFuturesPurchase = await poolManagerLogicProxy.totalFundValue();
          expect(fundValueAfterFuturesPurchase).to.be.closeTo(
            totalFundValueBefore.sub(openFee).sub(keeperFee),
            totalFundValueBefore.div(100), // price can vary it seems depending on oracle price update from Pyth network
          );

          ///
          /// We manipulate the Chainlink price of the asset and check its reflected in the fundValue
          ///
          if (manipulatePriceByPercent != 0) {
            const expectedProfitSUSD = await testHelpers.calculateProfitLoss({
              poolLogicProxy,
              marketAddress: ETH_FUTURES_MARKET,
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
            await testHelpers.manipulateChainLinkOracle(
              await assetHandler.priceAggregators(assets.weth),
              manipulatePriceByPercent,
            );
            const fundValueAfterPriceManipulation = await poolManagerLogicProxy.totalFundValue();
            // Assert that the fund value has changed by an expected amount
            // because of the manipulated Chainlink oracle price
            expect(fundValueAfterPriceManipulation).to.be.closeTo(
              expectedFundValue,
              expectedFundValue.div(1000).mul(leverage), // within 0.1-0.2%
            );
          } else {
            // If the price wasn't manipulated, then can close the position without an oracle price divergence error (checks Chainlink vs offchain Pyth price)
            const fundValueBeforeClose = await poolManagerLogicProxy.totalFundValue();
            const keeperFee = await testHelpers.getMinKeeperFee(ovmChainData.perpsV2.addressResolver);

            await testHelpers.closeOrLiquidateAndWithdrawMargin({
              poolLogicProxy,
              poolManager: manager,
              marketAddress: ETH_FUTURES_MARKET,
            });

            expect(await marketAssetGuard.getBalance(poolLogicProxy.address, ETH_FUTURES_MARKET)).to.equal(0);
            expect(await poolManagerLogicProxy["assetValue(address)"](ETH_FUTURES_MARKET)).to.equal(0);

            expect(await poolManagerLogicProxy.totalFundValue()).to.be.closeTo(
              fundValueBeforeClose.sub(keeperFee),
              fundValueBeforeClose.div(100).mul(leverage), // within 1-2% due to Chainlink pricing vs Pyth oracle pricing
            );
          }
        });
      };

      [
        {
          name: "3x long future leverage is too high",
          margin: ONE_THOUSAND,
          leverage: 3,
          isShort: false,
          manipulatePriceByPercent: 0,
        },
        {
          name: "3x short future leverage is too high",
          margin: ONE_THOUSAND,
          leverage: 3,
          isShort: true,
          manipulatePriceByPercent: 0,
        },
        {
          name: "Prices 1x long future correctly",
          margin: ONE_THOUSAND,
          leverage: 1,
          isShort: false,
          manipulatePriceByPercent: 0,
        },
        {
          name: "Prices 1x short future correctly",
          margin: ONE_THOUSAND,
          leverage: 1,
          isShort: true,
          manipulatePriceByPercent: 0,
        },
        {
          name: "Prices 2x long future correctly",
          margin: ONE_THOUSAND,
          leverage: 2,
          isShort: false,
          manipulatePriceByPercent: 0,
        },
        {
          name: "Prices 2x short future correctly",
          margin: ONE_THOUSAND,
          leverage: 2,
          isShort: true,
          manipulatePriceByPercent: 0,
        },
        {
          name: "Prices 1x long future correctly when baseAssetPrice Increases by 100%",
          margin: ONE_THOUSAND,
          leverage: 1,
          isShort: false,
          manipulatePriceByPercent: 100,
        },
        {
          name: "Prices 2x short future correctly when baseAssetPrice Increases by 100%",
          margin: ONE_THOUSAND,
          leverage: 2,
          isShort: true,
          manipulatePriceByPercent: 100,
        },
        {
          name: "Prices 2x long future correctly when baseAssetPrice Decreases by 50%",
          margin: ONE_THOUSAND,
          leverage: 2,
          isShort: false,
          manipulatePriceByPercent: -50,
        },
        {
          name: "Prices 2x short future correctly when baseAssetPrice Decreases by 50%",
          margin: ONE_THOUSAND,
          leverage: 2,
          isShort: true,
          manipulatePriceByPercent: -50,
        },
      ].forEach(balanceTest);
    });
  });
};
