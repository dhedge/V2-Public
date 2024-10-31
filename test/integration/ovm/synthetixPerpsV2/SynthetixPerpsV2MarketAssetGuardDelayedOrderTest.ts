import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { ethers } from "hardhat";
import { ovmChainData } from "../../../../config/chainData/ovmData";
import { AssetHandler, ISynthAddressProxy, PoolFactory, PoolLogic, PoolManagerLogic } from "../../../../types";
import { units } from "../../../testHelpers";
import { createFund } from "../../utils/createFund";
import { deployContracts, IDeployments } from "../../utils/deployContracts/deployContracts";
import { getAccountToken } from "../../utils/getAccountTokens";
import { utils } from "../../utils/utils";
import { perpsV2TestHelpers } from "./SynthetixPerpsV2TestHelpers";
const { assets } = ovmChainData;

// PerpsV2 supports delayed orders which means the manager submits an order and then it is picked up by a keeper
// If an investor withdraws while a delayed order is open we revert
describe("SynthetixPerpsV2MarketAssetGuard Delayed Order Tests", function () {
  let deployments: IDeployments;
  let susdProxy: ISynthAddressProxy;
  let logicOwner: SignerWithAddress, manager: SignerWithAddress;
  let poolFactory: PoolFactory, poolLogicProxy: PoolLogic, poolManagerLogicProxy: PoolManagerLogic;
  const ETH_FUTURES_MARKET = ovmChainData.perpsV2.ethMarket;
  const THOUSAND_SUSD = units(1000);
  let assetHandler: AssetHandler;

  utils.beforeAfterReset(before, after);
  utils.beforeAfterReset(beforeEach, afterEach);

  before(async () => {
    [logicOwner, manager] = await ethers.getSigners();
    deployments = await deployContracts("ovm");
    assetHandler = deployments.assetHandler;
    poolFactory = deployments.poolFactory;
    poolFactory.setExitCooldown(0);

    susdProxy = await ethers.getContractAt("ISynthAddressProxy", assets.susd);

    await getAccountToken(THOUSAND_SUSD, logicOwner.address, ovmChainData.synthetix.sUSDProxy_target_tokenState, 3);
    expect(await susdProxy.balanceOf(logicOwner.address)).to.equal(THOUSAND_SUSD);

    const fund = await createFund(poolFactory, logicOwner, manager, [{ asset: assets.susd, isDeposit: true }], {
      performance: ethers.BigNumber.from("0"),
      management: ethers.BigNumber.from("0"),
    });
    poolLogicProxy = fund.poolLogicProxy;
    poolManagerLogicProxy = fund.poolManagerLogicProxy;

    // Deploy the Perps guards with the new fund whitelisted for use
    await perpsV2TestHelpers.setup(deployments, ovmChainData, [fund.poolLogicProxy.address]);
    // Enable perps in the pool
    await fund.poolManagerLogicProxy
      .connect(manager)
      .changeAssets([{ asset: ETH_FUTURES_MARKET, isDeposit: false }], []);

    await susdProxy.approve(poolLogicProxy.address, THOUSAND_SUSD);
    await poolLogicProxy.deposit(assets.susd, THOUSAND_SUSD);
  });

  describe("WithdrawProcessing", () => {
    it("Reverts if manager has an open delayed order", async () => {
      await perpsV2TestHelpers.createDelayedOrder({
        poolLogicProxy,
        poolManager: manager,
        marketAddress: ETH_FUTURES_MARKET,
        margin: THOUSAND_SUSD,
        leverage: 1,
        isShort: true,
        baseAssetPrice: await assetHandler.getUSDPrice(assets.seth),
        skipOrderExecution: true,
      });

      // Assert all value is inside future
      expect(await susdProxy.balanceOf(poolLogicProxy.address)).to.equal(0);

      // Assert investor has no sUSD before withdraw
      expect(await susdProxy.balanceOf(logicOwner.address)).to.equal(0);

      // Withdraw 10%
      const balanceOfInvestor = await poolLogicProxy.balanceOf(logicOwner.address);
      await expect(poolLogicProxy.withdraw(balanceOfInvestor.div(10))).to.be.revertedWith("delayed order in progress");
    });
  });

  describe("getBalance", () => {
    it("Includes margin of delayed order", async () => {
      const keeperFee = await perpsV2TestHelpers.getMinKeeperFee(ovmChainData.perpsV2.addressResolver);
      const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();
      const fee = await perpsV2TestHelpers.createDelayedOrder({
        marketAddress: ETH_FUTURES_MARKET,
        poolLogicProxy: poolLogicProxy,
        poolManager: manager,
        margin: THOUSAND_SUSD,
        leverage: 1,
        isShort: false,
        baseAssetPrice: await assetHandler.getUSDPrice(assets.seth),
      });
      // Assert it's all in margin
      expect(await susdProxy.balanceOf(poolLogicProxy.address)).to.equal(0);

      expect(await poolManagerLogicProxy.totalFundValue()).to.be.closeTo(
        totalFundValueBefore.sub(fee).sub(keeperFee),
        totalFundValueBefore.div(100), // taking into account dynamic keeper fees
      );
    });
  });

  describe("Max Leverage Checks", () => {
    it("able to create position if leverage is ok (2x)", async () => {
      const keeperFee = await perpsV2TestHelpers.getMinKeeperFee(ovmChainData.perpsV2.addressResolver);
      const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();
      const fee = await perpsV2TestHelpers.createDelayedOrder({
        marketAddress: ETH_FUTURES_MARKET,
        poolLogicProxy: poolLogicProxy,
        poolManager: manager,
        margin: THOUSAND_SUSD,
        leverage: 2,
        isShort: false,
        baseAssetPrice: await assetHandler.getUSDPrice(assets.seth),
      });
      // Assert it's all in margin
      expect(await susdProxy.balanceOf(poolLogicProxy.address)).to.equal(0);

      expect(await poolManagerLogicProxy.totalFundValue()).to.be.closeTo(
        totalFundValueBefore.sub(fee).sub(keeperFee),
        totalFundValueBefore.div(100), // taking into account dynamic keeper fees
      );
    });

    it("fail to create position if leverage is too much (6x)", async () => {
      const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

      await expect(
        perpsV2TestHelpers.createDelayedOrder({
          marketAddress: ETH_FUTURES_MARKET,
          poolLogicProxy: poolLogicProxy,
          poolManager: manager,
          margin: THOUSAND_SUSD,
          leverage: 6,
          isShort: false,
          baseAssetPrice: await assetHandler.getUSDPrice(assets.seth),
        }),
      ).to.be.revertedWith("leverage must be less");

      expect(await poolManagerLogicProxy.totalFundValue()).eq(totalFundValueBefore);
    });

    it("able to withdraw margin if resulting leverage is ok (4x)", async () => {
      const keeperFee = await perpsV2TestHelpers.getMinKeeperFee(ovmChainData.perpsV2.addressResolver);
      const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();
      const fee = await perpsV2TestHelpers.createDelayedOrder({
        marketAddress: ETH_FUTURES_MARKET,
        poolLogicProxy: poolLogicProxy,
        poolManager: manager,
        margin: THOUSAND_SUSD,
        leverage: 2,
        isShort: true,
        baseAssetPrice: await assetHandler.getUSDPrice(assets.seth),
      });
      // Assert it's all in margin
      expect(await susdProxy.balanceOf(poolLogicProxy.address)).to.equal(0);

      const totalFundValueAfterFirst = await poolManagerLogicProxy.totalFundValue();
      expect(totalFundValueAfterFirst).to.be.closeTo(
        totalFundValueBefore.sub(fee).sub(keeperFee),
        totalFundValueBefore.div(100), // taking into account dynamic keeper fees
      );
      await perpsV2TestHelpers.increaseRealTime(2);
      const fee2 = await perpsV2TestHelpers.createDelayedOrder({
        marketAddress: ETH_FUTURES_MARKET,
        poolLogicProxy: poolLogicProxy,
        poolManager: manager,
        margin: THOUSAND_SUSD.mul(-1).div(2),
        leverage: 0, //only will do margin transfer
        isShort: true,
        baseAssetPrice: await assetHandler.getUSDPrice(assets.seth),
      });
      expect(await susdProxy.balanceOf(poolLogicProxy.address)).gt(0);
      expect(await poolManagerLogicProxy.totalFundValue()).to.be.closeTo(
        totalFundValueAfterFirst.sub(fee2),
        totalFundValueAfterFirst.div(100), // taking into account dynamic keeper fees
      );
    });

    it("fail to withdraw margin if resulting leverage is too much (> 5x)", async () => {
      const keeperFee = await perpsV2TestHelpers.getMinKeeperFee(ovmChainData.perpsV2.addressResolver);
      const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();
      const fee = await perpsV2TestHelpers.createDelayedOrder({
        marketAddress: ETH_FUTURES_MARKET,
        poolLogicProxy: poolLogicProxy,
        poolManager: manager,
        margin: THOUSAND_SUSD,
        leverage: 2,
        isShort: true,
        baseAssetPrice: await assetHandler.getUSDPrice(assets.seth),
      });
      // Assert it's all in margin
      expect(await susdProxy.balanceOf(poolLogicProxy.address)).to.equal(0);

      const totalFundValueAfterFirst = await poolManagerLogicProxy.totalFundValue();
      expect(totalFundValueAfterFirst).to.be.closeTo(
        totalFundValueBefore.sub(fee).sub(keeperFee),
        totalFundValueBefore.div(100), // taking into account dynamic keeper fees
      );
      await expect(
        perpsV2TestHelpers.createDelayedOrder({
          marketAddress: ETH_FUTURES_MARKET,
          poolLogicProxy: poolLogicProxy,
          poolManager: manager,
          margin: THOUSAND_SUSD.mul(-60).div(100),
          leverage: 0, //only will do margin transfer
          isShort: true,
          baseAssetPrice: await assetHandler.getUSDPrice(assets.seth),
        }),
      ).to.be.revertedWith("leverage must be less");
    });
  });
});
