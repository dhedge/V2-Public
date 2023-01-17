import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { ethers } from "hardhat";
import { ovmChainData } from "../../../../config/chainData/ovm-data";
import { AssetHandler, ISynthAddressProxy, PoolFactory, PoolLogic, PoolManagerLogic } from "../../../../types";
import { units } from "../../../TestHelpers";
import { createFund } from "../../utils/createFund";
import { deployContracts, IDeployments } from "../../utils/deployContracts/deployContracts";
import { getAccountToken } from "../../utils/getAccountTokens";
import { utils } from "../../utils/utils";
import { futuresTestHelpers } from "./FuturesTestHelpers";
const { assets } = ovmChainData;

const sUSDProxy_target_tokenState = "0x92bac115d89ca17fd02ed9357ceca32842acb4c2";
describe("FuturesMarketAssetGuard Withdraw Tests", function () {
  let deployments: IDeployments;
  let susdProxy: ISynthAddressProxy;
  let logicOwner: SignerWithAddress, manager: SignerWithAddress, otherInvestor: SignerWithAddress;
  let poolFactory: PoolFactory, poolLogicProxy: PoolLogic, poolManagerLogicProxy: PoolManagerLogic;
  const ETH_FUTURES_MARKET = ovmChainData.futures.ethMarket;
  const HUNDRED_SUSD = units(100);
  let assetHandler: AssetHandler;

  let snapId: string;

  after(async () => {
    await utils.evmRestoreSnap(snapId);
  });
  before(async function () {
    snapId = await utils.evmTakeSnap();
    [logicOwner, manager, otherInvestor] = await ethers.getSigners();
    deployments = await deployContracts("ovm");
    assetHandler = deployments.assetHandler;
    poolFactory = deployments.poolFactory;
    poolFactory.setExitCooldown(0);

    await futuresTestHelpers.setupFutures(deployments, ovmChainData);

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

  describe("WithdrawProcessing", () => {
    it("100% withdraw - short future with one investor receives correct amount of value", async () => {
      await futuresTestHelpers.createFuture({
        poolLogicProxy,
        poolManager: manager,
        futuresMarketAddress: ETH_FUTURES_MARKET,
        margin: HUNDRED_SUSD,
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

    it("100% withdraw - 10x long future with one investor receives correct amount of value", async () => {
      await futuresTestHelpers.createFuture({
        poolLogicProxy,
        poolManager: manager,
        futuresMarketAddress: ETH_FUTURES_MARKET,
        margin: HUNDRED_SUSD,
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

    it("100% withdraw - after future is closed, but margin still exists", async () => {
      await futuresTestHelpers.createFuture({
        poolLogicProxy,
        poolManager: manager,
        futuresMarketAddress: ETH_FUTURES_MARKET,
        margin: HUNDRED_SUSD,
        leverage: 10,
        isShort: false,
        baseAssetPrice: await assetHandler.getUSDPrice(assets.seth),
      });

      await futuresTestHelpers.closeFuture({
        poolLogicProxy,
        poolManager: manager,
        futuresMarketAddress: ETH_FUTURES_MARKET,
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

    it("Withdraw - that causes margin to drop below minMargin closes position", async () => {
      const futuresMarketSettings = await ethers.getContractAt(
        "IFuturesMarketSettings",
        ovmChainData.futures.futuresMarketSettings,
      );
      const minMargin = await futuresMarketSettings.minInitialMargin();

      // We need more than minMargin to pay fees to open the position
      const marginToDeposit = minMargin.add(minMargin.div(4));
      await futuresTestHelpers.createFuture({
        poolLogicProxy,
        poolManager: manager,
        futuresMarketAddress: ETH_FUTURES_MARKET,
        margin: marginToDeposit,
        leverage: 10,
        isShort: false,
        baseAssetPrice: await assetHandler.getUSDPrice(assets.seth),
      });

      // Assert all value is inside future
      expect(await susdProxy.balanceOf(poolLogicProxy.address)).to.equal(HUNDRED_SUSD.sub(marginToDeposit));
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

    it("50% withdraw - long future with one investor receives correct amount of value", async () => {
      await futuresTestHelpers.createFuture({
        poolLogicProxy,
        poolManager: manager,
        futuresMarketAddress: ETH_FUTURES_MARKET,
        margin: HUNDRED_SUSD,
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

      // Withdraw 1/2
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

    it("Two investors - 50% withdraw each - long future", async () => {
      // Setup second investor
      await getAccountToken(HUNDRED_SUSD, otherInvestor.address, sUSDProxy_target_tokenState, 3);
      await susdProxy.connect(otherInvestor).approve(poolLogicProxy.address, HUNDRED_SUSD);
      await poolLogicProxy.connect(otherInvestor).deposit(assets.susd, HUNDRED_SUSD);

      await futuresTestHelpers.createFuture({
        poolLogicProxy,
        poolManager: manager,
        futuresMarketAddress: ETH_FUTURES_MARKET,
        margin: HUNDRED_SUSD,
        leverage: 10,
        isShort: false,
        baseAssetPrice: await assetHandler.getUSDPrice(assets.seth),
      });

      // Snapshot fund value before withdraw
      const totalFundValueBeforeWithdraw = await poolManagerLogicProxy.totalFundValue();

      // Withdraw 1/2
      const balanceOfLogicOwner = await poolLogicProxy.balanceOf(logicOwner.address);
      const balanceOfOtherInvestor = await poolLogicProxy.balanceOf(otherInvestor.address);
      await poolLogicProxy.connect(logicOwner).withdraw(balanceOfLogicOwner.div(2));
      await poolLogicProxy.connect(otherInvestor).withdraw(balanceOfOtherInvestor.div(2));

      const sUSDBalanceOfLogicOwner = await susdProxy.balanceOf(logicOwner.address);
      // Need to convert to USD value before comparing to totalFundValue (which is denominated in USD not sUSD)
      const usdBalanceOfLogicOwnerAfterWithdraw = await poolManagerLogicProxy["assetValue(address,uint256)"](
        assets.susd,
        sUSDBalanceOfLogicOwner,
      );

      // Assert that one investor received 25% of fund value (withdrew 50%)
      expect(usdBalanceOfLogicOwnerAfterWithdraw).to.be.closeTo(
        totalFundValueBeforeWithdraw.div(4),
        totalFundValueBeforeWithdraw.div(1000),
      );

      const sUSDBalanceOfOtherInvestor = await susdProxy.balanceOf(otherInvestor.address);
      // Need to convert to USD value before comparing to totalFundValue (which is denominated in USD not sUSD)
      const usdBalanceOfOtherInvestorAfterWithdraw = await poolManagerLogicProxy["assetValue(address,uint256)"](
        assets.susd,
        sUSDBalanceOfOtherInvestor,
      );

      // Assert that one investor received 25% of fund value (withdrew 50%)
      expect(usdBalanceOfOtherInvestorAfterWithdraw).to.be.closeTo(
        totalFundValueBeforeWithdraw.div(4),
        totalFundValueBeforeWithdraw.div(1000),
      );

      // Assert that 50% has been withdrawn from the pool 50% is still in the pool
      expect(await poolManagerLogicProxy.totalFundValue()).to.be.closeTo(
        totalFundValueBeforeWithdraw.div(2),
        totalFundValueBeforeWithdraw.div(1000),
      );
    });
  });
});
