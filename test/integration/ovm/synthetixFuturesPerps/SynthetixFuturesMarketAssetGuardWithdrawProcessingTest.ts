import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { ethers } from "hardhat";
import { BigNumber } from "ethers";
import { ovmChainData } from "../../../../config/chainData/ovmData";
import { AssetHandler, ISynthAddressProxy, PoolFactory, PoolLogic, PoolManagerLogic } from "../../../../types";
import { units, toBytes32 } from "../../../testHelpers";
import { createFund } from "../../utils/createFund";
import { deployContracts, IDeployments } from "../../utils/deployContracts/deployContracts";
import { getAccountToken } from "../../utils/getAccountTokens";
import { utils } from "../../utils/utils";
import { PerpsV2TestHelpers } from "../synthetixPerpsV2/SynthetixPerpsV2TestHelpers";

const { assets } = ovmChainData;

export const CreateSynthetixFuturesMarketAssetGuardWithdrawProcessingTests = (
  testHelpers: PerpsV2TestHelpers,
  config: { ethMarket: string },
) => {
  describe("AssetGuard Withdraw Tests", function () {
    let deployments: IDeployments;
    let susdProxy: ISynthAddressProxy;
    let logicOwner: SignerWithAddress, manager: SignerWithAddress, otherInvestor: SignerWithAddress;
    let poolFactory: PoolFactory, poolLogicProxy: PoolLogic, poolManagerLogicProxy: PoolManagerLogic;
    const ETH_FUTURES_MARKET = config.ethMarket;
    const ONE_THOUSAND = units(1000);
    let assetHandler: AssetHandler;
    let keeperFee: BigNumber;

    utils.beforeAfterReset(before, after);
    utils.beforeAfterReset(beforeEach, afterEach);

    before(async () => {
      [logicOwner, manager, otherInvestor] = await ethers.getSigners();
      deployments = await deployContracts("ovm");
      assetHandler = deployments.assetHandler;
      poolFactory = deployments.poolFactory;
      poolFactory.setExitCooldown(0);

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
      await testHelpers.setup(deployments, ovmChainData, [fund.poolLogicProxy.address]);
      // Enable perps in the pool
      await fund.poolManagerLogicProxy
        .connect(manager)
        .changeAssets([{ asset: ETH_FUTURES_MARKET, isDeposit: false }], []);

      await susdProxy.approve(poolLogicProxy.address, ONE_THOUSAND);
      await poolLogicProxy.deposit(assets.susd, ONE_THOUSAND);

      keeperFee = await testHelpers.getMinKeeperFee(ovmChainData.perpsV2.addressResolver);
      keeperFee = await poolManagerLogicProxy["assetValue(address,uint256)"](assets.susd, keeperFee); // Convert to USD
    });

    describe("WithdrawProcessing", () => {
      utils.beforeAfterReset(beforeEach, afterEach);

      // Delayed closure of positions on withdrawal means that it's not possible to atomically close positions
      // Therefore closing position when margin is below minimum is no longer supported (reverts)
      it.skip("75% withdraw - short future - closes whole position when under minMargin", async () => {
        await testHelpers.createDelayedOrder({
          poolLogicProxy,
          poolManager: manager,
          marketAddress: ETH_FUTURES_MARKET,
          margin: ONE_THOUSAND,
          leverage: 1,
          isShort: true,
          baseAssetPrice: await assetHandler.getUSDPrice(assets.seth),
        });

        // Assert all value is inside future
        expect(await susdProxy.balanceOf(poolLogicProxy.address)).to.equal(0);
        // Snapshot fund value before withdraw
        const totalFundValueBeforeWithdraw = await poolManagerLogicProxy.totalFundValue();

        // Assert investor has no sUSD before withdraw
        expect(await susdProxy.balanceOf(logicOwner.address)).to.equal(0);

        // Withdraw 75%
        const balanceOfInvestor = await poolLogicProxy.balanceOf(logicOwner.address);
        await poolLogicProxy.withdraw(balanceOfInvestor.mul(75).div(100));

        const sUSDBalanceOfInvestorAfterWithdraw = await susdProxy.balanceOf(logicOwner.address);
        // Need to convert to USD value before comparing to totalFundValue (which is denominated in USD not sUSD)
        const usdBalanceOfInvestorAfterWithdraw = await poolManagerLogicProxy["assetValue(address,uint256)"](
          assets.susd,
          sUSDBalanceOfInvestorAfterWithdraw,
        );

        // Assert Investors Balance
        expect(usdBalanceOfInvestorAfterWithdraw).to.be.closeTo(
          totalFundValueBeforeWithdraw.mul(75).div(100),
          totalFundValueBeforeWithdraw.div(1000),
        );

        const sUSDBalanceOfPoolAfterWithdraw = await susdProxy.balanceOf(poolLogicProxy.address);
        // Need to convert to USD value before comparing to totalFundValue (which is denominated in USD not sUSD)
        const usdBalanceOfPoolAfterWithdraw = await poolManagerLogicProxy["assetValue(address,uint256)"](
          assets.susd,
          sUSDBalanceOfPoolAfterWithdraw,
        );

        // Assert Funds Balance
        expect(usdBalanceOfPoolAfterWithdraw).to.be.closeTo(
          totalFundValueBeforeWithdraw.mul(25).div(100),
          totalFundValueBeforeWithdraw.div(1000),
        );
      });

      // Delayed closure of positions on withdrawal means that it's not possible to atomically close positions
      // and withdrawal will fail because of increased leverage
      it.skip("100% withdraw - 10x long future with one investor receives correct amount of value", async () => {
        await testHelpers.createDelayedOrder({
          poolLogicProxy,
          poolManager: manager,
          marketAddress: ETH_FUTURES_MARKET,
          margin: ONE_THOUSAND,
          leverage: 10,
          isShort: false,
          baseAssetPrice: await assetHandler.getUSDPrice(assets.seth),
        });

        // Assert all value is inside future
        expect(await susdProxy.balanceOf(poolLogicProxy.address)).to.equal(0);
        // Snapshot fund value before withdraw
        const totalFundValueBeforeWithdraw = await poolManagerLogicProxy.totalFundValue();

        // Assert investor has no sUSD before withdraw
        expect(await susdProxy.balanceOf(logicOwner.address)).to.equal(0);

        // Withdraw All
        const balanceOfInvestor = await poolLogicProxy.balanceOf(logicOwner.address);
        await poolLogicProxy.withdraw(balanceOfInvestor);

        const sUSDBalanceOfInvestorAfterWithdraw = await susdProxy.balanceOf(logicOwner.address);
        // Need to convert to USD value before comparing to totalFundValue (which is denominated in USD not sUSD)
        const usdBalanceOfInvestorAfterWithdraw = await poolManagerLogicProxy["assetValue(address,uint256)"](
          assets.susd,
          sUSDBalanceOfInvestorAfterWithdraw,
        );
        // Assert Funds Balance
        expect(await poolManagerLogicProxy.totalFundValue()).to.equal(0);
        // Assert Investors Balance
        expect(usdBalanceOfInvestorAfterWithdraw).to.be.closeTo(
          totalFundValueBeforeWithdraw,
          totalFundValueBeforeWithdraw.div(1000),
        );
      });

      // Delayed closure of positions on withdrawal means that it's not possible to atomically close positions
      // and withdrawal will fail because of increased leverage
      it.skip("Withdraw - that causes margin to drop below minMargin closes position", async () => {
        const addressResolver = await ethers.getContractAt("IAddressResolver", ovmChainData.perpsV2.addressResolver);
        const perpsV2MarketSettingsAddress = await addressResolver.getAddress(toBytes32("PerpsV2MarketSettings"));
        const futuresMarketSettings = await ethers.getContractAt(
          "IPerpsV2MarketSettings",
          perpsV2MarketSettingsAddress,
        );
        const minMargin = await futuresMarketSettings.minInitialMargin();

        // We need more than minMargin to pay fees to open the position
        const marginToDeposit = minMargin.add(minMargin.div(4));
        await testHelpers.createDelayedOrder({
          poolLogicProxy,
          poolManager: manager,
          marketAddress: ETH_FUTURES_MARKET,
          margin: marginToDeposit,
          leverage: 10,
          isShort: false,
          baseAssetPrice: await assetHandler.getUSDPrice(assets.seth),
        });

        // Assert all value is inside future
        expect(await susdProxy.balanceOf(poolLogicProxy.address)).to.equal(ONE_THOUSAND.sub(marginToDeposit));
        // Snapshot fund value before withdraw
        const totalFundValueBeforeWithdraw = await poolManagerLogicProxy.totalFundValue();

        // Assert investor has no sUSD before withdraw
        expect(await susdProxy.balanceOf(logicOwner.address)).to.equal(0);

        // Withdraw 1/2 - This will reduce the futures position by half under the minMargin
        const balanceOfInvestor = await poolLogicProxy.balanceOf(logicOwner.address);
        await poolLogicProxy.withdraw(balanceOfInvestor.div(2));

        // Assert the whole futures position is closed
        expect(await poolManagerLogicProxy["assetValue(address)"](ETH_FUTURES_MARKET)).to.eq(0);

        const sUSDBalanceOfInvestorAfterWithdraw = await susdProxy.balanceOf(logicOwner.address);
        // Need to convert to USD value before comparing to totalFundValue (which is denominated in USD not sUSD)
        const usdBalanceOfInvestorAfterWithdraw = await poolManagerLogicProxy["assetValue(address,uint256)"](
          assets.susd,
          sUSDBalanceOfInvestorAfterWithdraw,
        );
        // Assert Funds Balance
        expect(await poolManagerLogicProxy.totalFundValue()).to.be.closeTo(
          totalFundValueBeforeWithdraw.div(2),
          totalFundValueBeforeWithdraw.div(1000),
        );
        // Assert Investors Balance
        expect(usdBalanceOfInvestorAfterWithdraw).to.be.closeTo(
          totalFundValueBeforeWithdraw.div(2),
          totalFundValueBeforeWithdraw.div(1000),
        );
      });

      it("50% withdraw - only margin, no position", async () => {
        await testHelpers.createDelayedOrder({
          poolLogicProxy,
          poolManager: manager,
          marketAddress: ETH_FUTURES_MARKET,
          margin: ONE_THOUSAND,
          leverage: 0, // no position just margin
          isShort: false,
          baseAssetPrice: await assetHandler.getUSDPrice(assets.seth),
        });

        // Snapshot fund value before withdraw
        const totalFundValueBeforeWithdraw = await poolManagerLogicProxy.totalFundValue();

        // Withdraw 50%
        const balanceOfInvestor = await poolLogicProxy.balanceOf(logicOwner.address);
        await poolLogicProxy.withdraw(balanceOfInvestor.div(2));

        const sUSDBalanceOfInvestorAfterWithdraw = await susdProxy.balanceOf(logicOwner.address);
        // Need to convert to USD value before comparing to totalFundValue (which is denominated in USD not sUSD)
        const usdBalanceOfInvestorAfterWithdraw = await poolManagerLogicProxy["assetValue(address,uint256)"](
          assets.susd,
          sUSDBalanceOfInvestorAfterWithdraw,
        );
        // Assert Funds Balance
        expect(await poolManagerLogicProxy.totalFundValue()).to.be.closeTo(
          totalFundValueBeforeWithdraw.div(2),
          totalFundValueBeforeWithdraw.div(1000),
        );
        // Assert Investors Balance
        expect(usdBalanceOfInvestorAfterWithdraw).to.be.closeTo(
          totalFundValueBeforeWithdraw.div(2),
          totalFundValueBeforeWithdraw.div(1000),
        );
      });

      it("100% withdraw - only margin, no position", async () => {
        await testHelpers.createDelayedOrder({
          poolLogicProxy,
          poolManager: manager,
          marketAddress: ETH_FUTURES_MARKET,
          margin: ONE_THOUSAND,
          leverage: 0, // no position just margin
          isShort: false,
          baseAssetPrice: await assetHandler.getUSDPrice(assets.seth),
        });

        // Snapshot fund value before withdraw
        const totalFundValueBeforeWithdraw = await poolManagerLogicProxy.totalFundValue();

        // Withdraw All
        const balanceOfInvestor = await poolLogicProxy.balanceOf(logicOwner.address);
        await poolLogicProxy.withdraw(balanceOfInvestor);

        const sUSDBalanceOfInvestorAfterWithdraw = await susdProxy.balanceOf(logicOwner.address);
        // Need to convert to USD value before comparing to totalFundValue (which is denominated in USD not sUSD)
        const usdBalanceOfInvestorAfterWithdraw = await poolManagerLogicProxy["assetValue(address,uint256)"](
          assets.susd,
          sUSDBalanceOfInvestorAfterWithdraw,
        );
        // Assert Funds Balance
        expect(await poolManagerLogicProxy.totalFundValue()).to.equal(0);
        // Assert Investors Balance
        expect(usdBalanceOfInvestorAfterWithdraw).to.be.closeTo(
          totalFundValueBeforeWithdraw,
          totalFundValueBeforeWithdraw.div(1000),
        );
      });

      it("25% withdraw - 1x long future with one investor receives correct amount of value", async () => {
        await testHelpers.createDelayedOrder({
          poolLogicProxy,
          poolManager: manager,
          marketAddress: ETH_FUTURES_MARKET,
          margin: ONE_THOUSAND,
          leverage: 1,
          isShort: false,
          baseAssetPrice: await assetHandler.getUSDPrice(assets.seth),
        });

        // Assert all value is inside future
        expect(await susdProxy.balanceOf(poolLogicProxy.address)).to.equal(0);
        const investorSusdBalanceBeforeWithdrawal = await susdProxy.balanceOf(logicOwner.address);
        const usdBalanceOfInvestorBeforeWithdrawal = await poolManagerLogicProxy["assetValue(address,uint256)"](
          assets.susd,
          investorSusdBalanceBeforeWithdrawal,
        );

        // Prepare withdrawal
        const totalFundValueBeforeWithdrawal = await poolManagerLogicProxy.totalFundValue();
        const balanceOfInvestor = await poolLogicProxy.balanceOf(logicOwner.address);
        const positionBefore = await testHelpers.getPosition({ poolLogicProxy, marketAddress: ETH_FUTURES_MARKET });
        // Update block timestamp so that the timestamp of offchain position closure submission is current
        await testHelpers.increaseRealTime(2); // 2 sec delay just to ensure the next block timestamp is higher

        // Withdraw and execute offchain transaction
        await poolLogicProxy.withdraw(balanceOfInvestor.div(4));
        await testHelpers.executeOffchainDelayedOrder(ETH_FUTURES_MARKET, manager, poolLogicProxy); // keeper partially closes the position after withdrawal

        // Get position data after withdrawal
        const totalFundValueAfterWithdrawal = await poolManagerLogicProxy.totalFundValue();
        const positionAfter = await testHelpers.getPosition({ poolLogicProxy, marketAddress: ETH_FUTURES_MARKET });

        const investorSusdBalanceAfterWithdrawal = await susdProxy.balanceOf(logicOwner.address);
        // Need to convert to USD value before comparing to totalFundValue (which is denominated in USD not sUSD)
        const usdBalanceOfInvestorAfterWithdrawal = await poolManagerLogicProxy["assetValue(address,uint256)"](
          assets.susd,
          investorSusdBalanceAfterWithdrawal,
        );

        // Assert Funds Balance: should be lower by the portion of withdrawal
        expect(totalFundValueAfterWithdrawal).to.be.closeTo(
          totalFundValueBeforeWithdrawal.mul(3).div(4), // 3/4
          totalFundValueBeforeWithdrawal.div(1333), // not more than 0.075% deviation (SLIPPAGE_DURING_WITHDRAWAL)
        );

        // Assert Investors Balance: should receive the withdrawn funds minus the fees
        const expectedUsdBalanceOfInvestorAfterWithdrawal = usdBalanceOfInvestorBeforeWithdrawal.add(
          totalFundValueBeforeWithdrawal.div(4).sub(keeperFee),
        );
        expect(usdBalanceOfInvestorAfterWithdrawal).to.be.lt(expectedUsdBalanceOfInvestorAfterWithdrawal);
        expect(usdBalanceOfInvestorAfterWithdrawal).to.be.closeTo(
          expectedUsdBalanceOfInvestorAfterWithdrawal,
          usdBalanceOfInvestorAfterWithdrawal.div(800), // not more than 0.125% deviation (SLIPPAGE_DURING_WITHDRAWAL)
        );

        // Assert Long/Short position should be partially closed and therefore leverage constant
        expect(positionAfter.margin).to.be.closeTo(
          positionBefore.margin.mul(3).div(4),
          positionBefore.margin.div(500), // Should be within 0.2%. Could be some movement due to price oracle changes
        );
        expect(positionAfter.leverage).to.be.closeTo(positionBefore.leverage, positionBefore.leverage.div(100)); // Should be within 1%. Could be some movement due to price oracle changes
      });

      it("Two investors - 20% withdraw each - short future", async () => {
        // Setup second investor
        await getAccountToken(
          ONE_THOUSAND,
          otherInvestor.address,
          ovmChainData.synthetix.sUSDProxy_target_tokenState,
          3,
        );
        await susdProxy.connect(otherInvestor).approve(poolLogicProxy.address, ONE_THOUSAND);
        await poolLogicProxy.connect(otherInvestor).deposit(assets.susd, ONE_THOUSAND);

        await testHelpers.createDelayedOrder({
          poolLogicProxy,
          poolManager: manager,
          marketAddress: ETH_FUTURES_MARKET,
          margin: ONE_THOUSAND,
          leverage: 1,
          isShort: true,
          baseAssetPrice: await assetHandler.getUSDPrice(assets.seth),
        });

        // Snapshot fund value before withdraw
        const totalFundValueBeforeWithdraw = await poolManagerLogicProxy.totalFundValue();

        // Withdraw 1/5
        const balanceOfLogicOwner = await poolLogicProxy.balanceOf(logicOwner.address);
        const balanceOfOtherInvestor = await poolLogicProxy.balanceOf(otherInvestor.address);
        const positionBefore = await testHelpers.getPosition({ poolLogicProxy, marketAddress: ETH_FUTURES_MARKET });
        await poolLogicProxy.connect(logicOwner).withdraw(balanceOfLogicOwner.div(5));
        await testHelpers.executeOffchainDelayedOrder(ETH_FUTURES_MARKET, manager, poolLogicProxy);
        const positionAfterFirst = await testHelpers.getPosition({ poolLogicProxy, marketAddress: ETH_FUTURES_MARKET });
        const totalFundValueAfterFirstWithdrawal = await poolManagerLogicProxy.totalFundValue();
        await poolLogicProxy.connect(otherInvestor).withdraw(balanceOfOtherInvestor.div(5));
        await testHelpers.executeOffchainDelayedOrder(ETH_FUTURES_MARKET, manager, poolLogicProxy);
        const positionAfterSecond = await testHelpers.getPosition({
          poolLogicProxy,
          marketAddress: ETH_FUTURES_MARKET,
        });
        const totalFundValueAfterSecondWithdrawal = await poolManagerLogicProxy.totalFundValue();

        const sUSDBalanceOfLogicOwner = await susdProxy.balanceOf(logicOwner.address);
        const sUSDBalanceOfOtherInvestor = await susdProxy.balanceOf(logicOwner.address);

        // Need to convert to USD value before comparing to totalFundValue (which is denominated in USD not sUSD)
        const usdBalanceOfLogicOwnerAfterWithdraw = await poolManagerLogicProxy["assetValue(address,uint256)"](
          assets.susd,
          sUSDBalanceOfLogicOwner,
        );
        const usdBalanceOfOtherInvestorAfterWithdraw = await poolManagerLogicProxy["assetValue(address,uint256)"](
          assets.susd,
          sUSDBalanceOfOtherInvestor,
        );

        // Assert that one investor received 10% of fund value (withdrew 20%)
        const expectedWithdrawnValueByInvestor = totalFundValueBeforeWithdraw.div(2).div(5);
        expect(usdBalanceOfLogicOwnerAfterWithdraw).to.be.closeTo(
          expectedWithdrawnValueByInvestor.sub(keeperFee),
          totalFundValueBeforeWithdraw.div(1000),
        );

        // Assert that the other investor received 10% of fund value (withdrew 20%)
        expect(usdBalanceOfOtherInvestorAfterWithdraw).to.be.closeTo(
          expectedWithdrawnValueByInvestor.sub(keeperFee),
          totalFundValueBeforeWithdraw.div(1000),
        );

        // Assert that 10% has been withdrawn after the first withdrawal
        expect(totalFundValueAfterFirstWithdrawal).to.be.closeTo(
          totalFundValueBeforeWithdraw.mul(9).div(10),
          totalFundValueBeforeWithdraw.div(1000),
        );

        // Assert that 20% has been withdrawn from the pool in total (80% is still in the pool)
        expect(totalFundValueAfterSecondWithdrawal).to.be.closeTo(
          totalFundValueBeforeWithdraw.mul(8).div(10),
          totalFundValueBeforeWithdraw.div(1000),
        );

        // Assert Long/Short position should be partially closed and therefore leverage constant
        // Should be within 1%. Could be some movement due to price oracle changes
        expect(positionAfterFirst.leverage).to.be.closeTo(positionBefore.leverage, positionBefore.leverage.div(100));
        expect(positionAfterSecond.leverage).to.be.closeTo(
          positionAfterFirst.leverage,
          positionAfterFirst.leverage.div(100),
        );
      });

      it("75% withdraw fails on withdrawal too large - long future", async () => {
        await testHelpers.createDelayedOrder({
          poolLogicProxy,
          poolManager: manager,
          marketAddress: ETH_FUTURES_MARKET,
          margin: ONE_THOUSAND,
          leverage: 2,
          isShort: false,
          baseAssetPrice: await assetHandler.getUSDPrice(assets.seth),
        });

        // Assert all value is inside future
        expect(await susdProxy.balanceOf(poolLogicProxy.address)).to.equal(0);
        // Snapshot fund value before withdraw

        // Withdraw 3/4 should fail
        const balanceOfInvestor = await poolLogicProxy.balanceOf(logicOwner.address);
        await expect(poolLogicProxy.withdraw(balanceOfInvestor.mul(3).div(4))).to.be.revertedWith(
          "perp v2 withdrawal too large",
        );
      });

      it("Two investors - 80% withdraw each - long future", async () => {
        // Setup second investor
        await getAccountToken(
          ONE_THOUSAND,
          otherInvestor.address,
          ovmChainData.synthetix.sUSDProxy_target_tokenState,
          3,
        );
        await susdProxy.connect(otherInvestor).approve(poolLogicProxy.address, ONE_THOUSAND);
        await poolLogicProxy.connect(otherInvestor).deposit(assets.susd, ONE_THOUSAND);

        await testHelpers.createDelayedOrder({
          poolLogicProxy,
          poolManager: manager,
          marketAddress: ETH_FUTURES_MARKET,
          margin: ONE_THOUSAND,
          leverage: 1,
          isShort: true,
          baseAssetPrice: await assetHandler.getUSDPrice(assets.seth),
        });

        // Snapshot fund value before withdraw
        const totalFundValueBeforeWithdraw = await poolManagerLogicProxy.totalFundValue();

        // Pool token balances
        const balanceOfLogicOwner = await poolLogicProxy.balanceOf(logicOwner.address);
        const balanceOfOtherInvestor = await poolLogicProxy.balanceOf(otherInvestor.address);
        const totalSupply = await poolLogicProxy.totalSupply();
        // Update block timestamp
        await testHelpers.increaseRealTime(2); // 2 sec delay just to ensure the next block timestamp is higher

        // Withdraw 4/5
        await poolLogicProxy.connect(logicOwner).withdraw(balanceOfLogicOwner.mul(4).div(5));
        await testHelpers.executeOffchainDelayedOrder(ETH_FUTURES_MARKET, manager, poolLogicProxy);
        // Second withdrawal should fail because the temporary leverage after withdrawal is too high
        await expect(poolLogicProxy.connect(otherInvestor).withdraw(balanceOfOtherInvestor)).to.be.revertedWith(
          "perp v2 withdrawal too large",
        );

        const sUSDBalanceOfLogicOwner = await susdProxy.balanceOf(logicOwner.address);
        // Need to convert to USD value before comparing to totalFundValue (which is denominated in USD not sUSD)
        const usdBalanceOfLogicOwnerAfterWithdraw = await poolManagerLogicProxy["assetValue(address,uint256)"](
          assets.susd,
          sUSDBalanceOfLogicOwner,
        );

        // Assert that one investor received 40% of fund value (withdrew 80%).
        // Adjusted for fractional ownership for the investor of the total pool size
        const expectedWithdrawnValueByInvestor = totalFundValueBeforeWithdraw
          .mul(balanceOfLogicOwner)
          .div(totalSupply)
          .mul(4)
          .div(5);
        expect(usdBalanceOfLogicOwnerAfterWithdraw).to.be.closeTo(
          expectedWithdrawnValueByInvestor.sub(keeperFee),
          totalFundValueBeforeWithdraw.div(1000),
        );

        // Assert that 80% has been withdrawn from the pool (20% is still in the pool)
        expect(await poolManagerLogicProxy.totalFundValue()).to.be.closeTo(
          totalFundValueBeforeWithdraw.sub(expectedWithdrawnValueByInvestor),
          totalFundValueBeforeWithdraw.div(1000),
        );
      });
    });
  });
};
