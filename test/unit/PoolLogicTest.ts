import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { artifacts, ethers, upgrades } from "hardhat";

import { updateChainlinkAggregators } from "../TestHelpers";
import { MockContract, PoolFactory, PoolLogic } from "../../types";

const ONE_SECOND = 1;
const ONE_MINUTE = ONE_SECOND * 60;
const ONE_HOUR = ONE_MINUTE * 60;
const ONE_DAY = ONE_HOUR * 24;

const getBlockTime = async () => (await ethers.provider.getBlock(await ethers.provider.getBlockNumber())).timestamp;

const calcRemainingCooldown = (lastCooldown: number, lastDepositTime: number, blockTime: number) => {
  const cooldownEndsAt = lastCooldown + lastDepositTime;
  return cooldownEndsAt < blockTime ? 0 : cooldownEndsAt - blockTime;
};

const amount = 42 * 1e6;

describe("dHEDGE Pool Deposit", () => {
  let manager: SignerWithAddress, investor: SignerWithAddress, dao: SignerWithAddress;
  let poolFactory: PoolFactory;
  let poolLogicProxy: PoolLogic;
  let usdcProxy: MockContract, usdcPriceFeed: MockContract;
  let usdcAddress: string, managerAddress: string, investorAddress: string;

  beforeEach(async () => {
    [manager, investor, dao] = await ethers.getSigners();
    managerAddress = manager.address;
    investorAddress = investor.address;

    const MockContract = await ethers.getContractFactory("MockContract");
    usdcProxy = await MockContract.deploy();
    usdcAddress = usdcProxy.address;
    usdcPriceFeed = await MockContract.deploy();

    const PoolLogic = await ethers.getContractFactory("PoolLogic");
    const poolLogic = await PoolLogic.deploy();

    const PoolManagerLogic = await ethers.getContractFactory("PoolManagerLogic");
    const poolManagerLogic = await PoolManagerLogic.deploy();

    await usdcProxy.givenCalldataReturnUint(
      new ethers.utils.Interface((await artifacts.readArtifact("ERC20Upgradeable")).abi).encodeFunctionData(
        "decimals",
        [],
      ),
      "6",
    );

    const AssetHandlerLogic = await ethers.getContractFactory(
      "contracts/priceAggregators/AssetHandler.sol:AssetHandler",
    );
    const assetHandlerInitAssets = [{ asset: usdcAddress, assetType: 0, aggregator: usdcPriceFeed.address }];
    const assetHandler = await upgrades.deployProxy(AssetHandlerLogic, [assetHandlerInitAssets]);
    await assetHandler.deployed();

    const Governance = await ethers.getContractFactory("Governance");
    const governance = await Governance.deploy();

    const PoolFactory = await ethers.getContractFactory("PoolFactory");
    poolFactory = <PoolFactory>(
      await upgrades.deployProxy(PoolFactory, [
        poolLogic.address,
        poolManagerLogic.address,
        assetHandler.address,
        dao.address,
        governance.address,
      ])
    );

    const ERC20Guard = await ethers.getContractFactory("contracts/guards/assetGuards/ERC20Guard.sol:ERC20Guard");
    const erc20Guard = await ERC20Guard.deploy();
    erc20Guard.deployed();
    await governance.setAssetGuard(0, erc20Guard.address);

    await poolFactory.createFund(false, manager.address, "String0", "String1", "String3", 0, 0, [
      { asset: usdcAddress, isDeposit: true },
    ]);
    const pools = await poolFactory.getDeployedFunds();
    poolLogicProxy = PoolLogic.attach(pools[0]);

    await updateChainlinkAggregators(usdcPriceFeed, await MockContract.deploy(), await MockContract.deploy());
  });

  describe("receiverWhitelist", () => {
    it("cannot transfer tokens while under lockup", async () => {
      await poolLogicProxy.depositFor(investorAddress, usdcAddress, amount);
      expect(await poolLogicProxy.getExitRemainingCooldown(investorAddress)).to.equal(86400);
      await expect(
        poolLogicProxy.connect(investor).transfer(dao.address, await poolLogicProxy.balanceOf(managerAddress)),
      ).to.be.revertedWith("cooldown active");
    });

    it("can transfer tokens under lockup to addresses in receiverWhitelist", async () => {
      await poolLogicProxy.depositFor(investorAddress, usdcAddress, amount);
      expect(await poolLogicProxy.getExitRemainingCooldown(investorAddress)).to.equal(86400);
      await poolFactory.addReceiverWhitelist(dao.address);
      await poolLogicProxy.connect(investor).transfer(dao.address, await poolLogicProxy.balanceOf(managerAddress));
    });

    it("removing an address for receiverWhitelist stops it from being able to receive tokens under lockup", async () => {
      await poolLogicProxy.depositFor(investorAddress, usdcAddress, amount);
      expect(await poolLogicProxy.getExitRemainingCooldown(investorAddress)).to.equal(86400);
      await poolFactory.addReceiverWhitelist(dao.address);
      const balance = await poolLogicProxy.balanceOf(managerAddress);
      await poolLogicProxy.connect(investor).transfer(dao.address, balance.div(2));
      await poolFactory.removeReceiverWhitelist(dao.address);
      await expect(poolLogicProxy.connect(investor).transfer(dao.address, balance.div(2))).to.revertedWith(
        "cooldown active",
      );
    });
  });

  describe("calculateCooldown calculates exit cooldown correctly", () => {
    it("should return default cooldown when subsequent larger deposit during early cooldown", async () => {
      const currentBalance = 100;
      const liquidityMinted = currentBalance * 4;
      const newCooldown = ONE_DAY;
      const blockTime = await getBlockTime();
      const lastCooldown = ONE_DAY;
      const lastDepositTime = blockTime - ONE_MINUTE - ONE_SECOND;
      const calculated = (
        await poolLogicProxy.calculateCooldown(
          currentBalance,
          liquidityMinted,
          newCooldown,
          lastCooldown,
          lastDepositTime,
          blockTime,
        )
      ).toNumber();
      expect(calculated).to.equal(ONE_DAY);
      expect(calculated).to.be.greaterThan(calcRemainingCooldown(lastCooldown, lastDepositTime, blockTime));
    });

    it("should return default cooldown when subsequent larger deposit during late cooldown", async () => {
      const currentBalance = 999;
      const liquidityMinted = currentBalance * 3;
      const newCooldown = ONE_DAY;
      const blockTime = await getBlockTime();
      const lastCooldown = ONE_DAY;
      const lastDepositTime = blockTime - ONE_HOUR * 23 - ONE_MINUTE * 59 - ONE_SECOND * 59;
      const calculated = (
        await poolLogicProxy.calculateCooldown(
          currentBalance,
          liquidityMinted,
          newCooldown,
          lastCooldown,
          lastDepositTime,
          blockTime,
        )
      ).toNumber();
      expect(calculated).to.equal(ONE_DAY);
      expect(calculated).to.be.greaterThan(calcRemainingCooldown(lastCooldown, lastDepositTime, blockTime));
    });

    it("should return remaining+additional cooldown when subsequent smaller deposit during early cooldown (remaining+additional doesn't exceed new cooldown)", async () => {
      const currentBalance = 1000;
      const liquidityMinted = 10;
      const newCooldown = ONE_DAY;
      const blockTime = await getBlockTime();
      const lastCooldown = ONE_DAY;
      const lastDepositTime = blockTime - ONE_HOUR;
      const calculated = (
        await poolLogicProxy.calculateCooldown(
          currentBalance,
          liquidityMinted,
          newCooldown,
          lastCooldown,
          lastDepositTime,
          blockTime,
        )
      ).toNumber();
      const remaining = calcRemainingCooldown(lastCooldown, lastDepositTime, blockTime);
      expect(calculated).to.equal(remaining + 864);
      expect(calculated).to.be.greaterThan(remaining);
    });

    it("should return default cooldown when subsequent smaller deposit during early cooldown (remaining+additional exceed new cooldown)", async () => {
      const currentBalance = 1000;
      const liquidityMinted = 10;
      const newCooldown = ONE_DAY;
      const blockTime = await getBlockTime();
      const lastCooldown = ONE_DAY;
      const lastDepositTime = blockTime - ONE_SECOND;
      const calculated = (
        await poolLogicProxy.calculateCooldown(
          currentBalance,
          liquidityMinted,
          newCooldown,
          lastCooldown,
          lastDepositTime,
          blockTime,
        )
      ).toNumber();
      expect(calculated).to.equal(ONE_DAY);
      expect(calculated).to.be.greaterThan(calcRemainingCooldown(lastCooldown, lastDepositTime, blockTime));
    });

    it("should return remaining+additional cooldown when subsequent smaller deposit during late cooldown", async () => {
      const currentBalance = 1000;
      const liquidityMinted = 10;
      const newCooldown = ONE_DAY;
      const blockTime = await getBlockTime();
      const lastCooldown = ONE_DAY;
      const lastDepositTime = blockTime - ONE_HOUR * 23 - ONE_MINUTE * 42;
      const calculated = (
        await poolLogicProxy.calculateCooldown(
          currentBalance,
          liquidityMinted,
          newCooldown,
          lastCooldown,
          lastDepositTime,
          blockTime,
        )
      ).toNumber();
      const remaining = calcRemainingCooldown(lastCooldown, lastDepositTime, blockTime);
      expect(calculated).to.equal(remaining + 864);
      expect(calculated).to.be.greaterThan(remaining);
    });

    it("should return default cooldown when subsequent larger deposit after cooldown", async () => {
      const currentBalance = 123;
      const liquidityMinted = currentBalance * 5;
      const newCooldown = ONE_DAY;
      const blockTime = await getBlockTime();
      const lastCooldown = ONE_DAY;
      const lastDepositTime = blockTime - ONE_DAY * 10;
      const calculated = (
        await poolLogicProxy.calculateCooldown(
          currentBalance,
          liquidityMinted,
          newCooldown,
          lastCooldown,
          lastDepositTime,
          blockTime,
        )
      ).toNumber();
      expect(calculated).to.equal(ONE_DAY);
      expect(calculated).to.be.greaterThan(calcRemainingCooldown(lastCooldown, lastDepositTime, blockTime));
    });

    it("should return additional cooldown when subsequent smaller deposit after cooldown", async () => {
      const currentBalance = 10000;
      const liquidityMinted = 1;
      const newCooldown = ONE_DAY;
      const blockTime = await getBlockTime();
      const lastCooldown = ONE_DAY;
      const lastDepositTime = blockTime - ONE_DAY * 10;
      const calculated = (
        await poolLogicProxy.calculateCooldown(
          currentBalance,
          liquidityMinted,
          newCooldown,
          lastCooldown,
          lastDepositTime,
          blockTime,
        )
      ).toNumber();
      expect(calculated).to.equal(8);
      expect(calculated).to.be.greaterThan(calcRemainingCooldown(lastCooldown, lastDepositTime, blockTime));
    });

    it("should return default cooldown when subsequent equal deposit during cooldown", async () => {
      const currentBalance = 432;
      const liquidityMinted = 432;
      const newCooldown = ONE_DAY;
      const blockTime = await getBlockTime();
      const lastCooldown = ONE_DAY;
      const lastDepositTime = blockTime - ONE_HOUR * 22 - ONE_SECOND * 59;
      const calculated = (
        await poolLogicProxy.calculateCooldown(
          currentBalance,
          liquidityMinted,
          newCooldown,
          lastCooldown,
          lastDepositTime,
          blockTime,
        )
      ).toNumber();
      expect(calculated).to.equal(ONE_DAY);
      expect(calculated).to.be.greaterThan(calcRemainingCooldown(lastCooldown, lastDepositTime, blockTime));
    });

    it("should return default cooldown when subsequent equal deposit after cooldown", async () => {
      const currentBalance = 42003;
      const liquidityMinted = currentBalance;
      const newCooldown = ONE_DAY;
      const blockTime = await getBlockTime();
      const lastCooldown = ONE_DAY;
      const lastDepositTime = blockTime - ONE_DAY * 42;
      const calculated = (
        await poolLogicProxy.calculateCooldown(
          currentBalance,
          liquidityMinted,
          newCooldown,
          lastCooldown,
          lastDepositTime,
          blockTime,
        )
      ).toNumber();
      expect(calculated).to.equal(ONE_DAY);
      expect(calculated).to.be.greaterThan(calcRemainingCooldown(lastCooldown, lastDepositTime, blockTime));
    });

    it("should return remaining cooldown when subsequent zero liquidity deposit during cooldown", async () => {
      const currentBalance = 428987;
      const liquidityMinted = 0;
      const newCooldown = ONE_DAY;
      const blockTime = await getBlockTime();
      const lastCooldown = ONE_DAY;
      const lastDepositTime = blockTime - ONE_MINUTE * 2;
      const calculated = (
        await poolLogicProxy.calculateCooldown(
          currentBalance,
          liquidityMinted,
          newCooldown,
          lastCooldown,
          lastDepositTime,
          blockTime,
        )
      ).toNumber();
      expect(calculated).to.equal(calcRemainingCooldown(lastCooldown, lastDepositTime, blockTime));
    });

    it("should return zero cooldown when subsequent zero liquidity deposit after cooldown", async () => {
      const currentBalance = 425698;
      const liquidityMinted = 0;
      const newCooldown = ONE_DAY;
      const blockTime = await getBlockTime();
      const lastCooldown = ONE_DAY;
      const lastDepositTime = blockTime - ONE_DAY * 20;
      const calculated = (
        await poolLogicProxy.calculateCooldown(
          currentBalance,
          liquidityMinted,
          newCooldown,
          lastCooldown,
          lastDepositTime,
          blockTime,
        )
      ).toNumber();
      expect(calculated).to.equal(0);
    });

    it("should return zero cooldown when first zero liquidity deposit", async () => {
      const currentBalance = 0;
      const liquidityMinted = 0;
      const newCooldown = ONE_DAY;
      const blockTime = await getBlockTime();
      const lastCooldown = 0;
      const lastDepositTime = 0;
      const calculated = (
        await poolLogicProxy.calculateCooldown(
          currentBalance,
          liquidityMinted,
          newCooldown,
          lastCooldown,
          lastDepositTime,
          blockTime,
        )
      ).toNumber();
      expect(calculated).to.equal(0);
    });

    it("should return default cooldown when first larger deposit than current token balance", async () => {
      const currentBalance = 1000;
      const liquidityMinted = 42000;
      const newCooldown = ONE_DAY;
      const blockTime = await getBlockTime();
      const lastCooldown = 0;
      const lastDepositTime = 0;
      const calculated = (
        await poolLogicProxy.calculateCooldown(
          currentBalance,
          liquidityMinted,
          newCooldown,
          lastCooldown,
          lastDepositTime,
          blockTime,
        )
      ).toNumber();
      expect(calculated).to.equal(ONE_DAY);
    });

    it("should return additional cooldown when first smaller deposit than current token balance", async () => {
      const currentBalance = 10000;
      const liquidityMinted = 10;
      const newCooldown = ONE_DAY;
      const blockTime = await getBlockTime();
      const lastCooldown = 0;
      const lastDepositTime = 0;
      const calculated = (
        await poolLogicProxy.calculateCooldown(
          currentBalance,
          liquidityMinted,
          newCooldown,
          lastCooldown,
          lastDepositTime,
          blockTime,
        )
      ).toNumber();
      expect(calculated).to.equal(86);
    });

    /*
      User deposits money to buy 100_000 tokens via deposiFor(), receives 24 hour lockup.
      One second later user deposits money to buy 1 token via depositForWithCustomCooldown() (ezswapper) with a 5 minutes lockup
      Lockup should not be reset therefore resulting lockup is 23 hours 59 minutes 59 seconds
     */
    it("should return remaining cooldown when subsequent smaller deposit during early cooldown with new short cooldown", async () => {
      const currentBalance = 100000;
      const liquidityMinted = 1;
      const newCooldown = ONE_MINUTE * 5;
      const blockTime = await getBlockTime();
      const lastCooldown = ONE_DAY;
      const lastDepositTime = blockTime - ONE_SECOND;
      const calculated = (
        await poolLogicProxy.calculateCooldown(
          currentBalance,
          liquidityMinted,
          newCooldown,
          lastCooldown,
          lastDepositTime,
          blockTime,
        )
      ).toNumber();
      expect(calculated).to.equal(ONE_HOUR * 23 + ONE_MINUTE * 59 + ONE_SECOND * 59);
    });

    /*
      User deposits money to buy 100_000 tokens via deposiFor(), receives 24 hour lockup.
      One second later user deposits money to buy 500_000 tokens via depositForWithCustomCooldown() (ezswapper) with a 5 minutes lockup
      Lockup should not be reset therefore resulting lockup is 23 hours 59 minutes 59 seconds
     */
    it("should return remaining cooldown when subsequent larger deposit during early cooldown with new short cooldown", async () => {
      const currentBalance = 100000;
      const liquidityMinted = currentBalance * 5;
      const newCooldown = ONE_MINUTE * 5;
      const blockTime = await getBlockTime();
      const lastCooldown = ONE_DAY;
      const lastDepositTime = blockTime - ONE_SECOND;
      const calculated = (
        await poolLogicProxy.calculateCooldown(
          currentBalance,
          liquidityMinted,
          newCooldown,
          lastCooldown,
          lastDepositTime,
          blockTime,
        )
      ).toNumber();
      expect(calculated).to.equal(ONE_HOUR * 23 + ONE_MINUTE * 59 + ONE_SECOND * 59);
    });

    /*
      User deposits money to buy 1000 tokens via deposiFor(), receives 24 hour lockup.
      After 23 hours and 50 minutes user deposits money to buy 3000 tokens via depositForWithCustomCooldown() (ezswapper) with a 5 minutes lockup
      10 minutes > 5 minutes so therefore lockup is 10 minutes
     */
    it("should return remaining cooldown when subsequent larger deposit during last 10 minutes cooldown with new short cooldown", async () => {
      const currentBalance = 1000;
      const liquidityMinted = currentBalance * 3;
      const newCooldown = ONE_MINUTE * 5;
      const blockTime = await getBlockTime();
      const lastCooldown = ONE_DAY;
      const lastDepositTime = blockTime - ONE_HOUR * 23 - ONE_MINUTE * 50;
      const calculated = (
        await poolLogicProxy.calculateCooldown(
          currentBalance,
          liquidityMinted,
          newCooldown,
          lastCooldown,
          lastDepositTime,
          blockTime,
        )
      ).toNumber();
      expect(calculated).to.equal(600);
    });

    /*
      User deposits money to buy 1000 tokens via deposiFor(), receives 24 hour lockup.
      After 23 hours and 59 minutes user deposits money to buy 3000 tokens via depositForWithCustomCooldown() (ezswapper) with a 5 minutes lockup
      1 minute < 5 minutes so therefore lockup is 5 minutes
     */
    it("should return new short cooldown when subsequent larger deposit during last 1 minute cooldown with new short cooldown", async () => {
      const currentBalance = 1000;
      const liquidityMinted = currentBalance * 3;
      const newCooldown = ONE_MINUTE * 5;
      const blockTime = await getBlockTime();
      const lastCooldown = ONE_DAY;
      const lastDepositTime = blockTime - ONE_HOUR * 23 - ONE_MINUTE * 59;
      const calculated = (
        await poolLogicProxy.calculateCooldown(
          currentBalance,
          liquidityMinted,
          newCooldown,
          lastCooldown,
          lastDepositTime,
          blockTime,
        )
      ).toNumber();
      expect(calculated).to.equal(300);
      expect(calculated).to.be.greaterThan(calcRemainingCooldown(lastCooldown, lastDepositTime, blockTime));
    });

    /*
      User deposits money to buy 1000 tokens via deposiFor(), receives 24 hour lockup.
      After 23 hours and 59 minutes user deposits money to buy 10 tokens via depositForWithCustomCooldown() (ezswapper) with a 5 minutes lockup
      Lockup is remaining cooldown + additional cooldown calculated based on 5 minutes lockup
     */
    it("should return remaining+additional cooldown when subsequent smaller deposit during last 1 minute cooldown with new short cooldown", async () => {
      const currentBalance = 1000;
      const liquidityMinted = 10;
      const newCooldown = ONE_MINUTE * 5;
      const blockTime = await getBlockTime();
      const lastCooldown = ONE_DAY;
      const lastDepositTime = blockTime - ONE_HOUR * 23 - ONE_MINUTE * 59;
      const calculated = (
        await poolLogicProxy.calculateCooldown(
          currentBalance,
          liquidityMinted,
          newCooldown,
          lastCooldown,
          lastDepositTime,
          blockTime,
        )
      ).toNumber();
      const remaining = calcRemainingCooldown(lastCooldown, lastDepositTime, blockTime);
      expect(calculated).to.equal(remaining + 3);
      expect(calculated).to.be.greaterThan(remaining);
    });

    /*
      User deposits money to buy 1000 tokens via deposiFor(), receives 24 hour lockup.
      After 23 hours and 59 minutes user deposits money to buy 1000 tokens via depositForWithCustomCooldown() (ezswapper) with a 5 minutes lockup
      1 minute < 5 minutes so therefore lockup is 5 minutes
     */
    it("should return new short cooldown when subsequent equal deposit during last 1 minute cooldown with new short cooldown", async () => {
      const currentBalance = 1000;
      const liquidityMinted = currentBalance;
      const newCooldown = ONE_MINUTE * 5;
      const blockTime = await getBlockTime();
      const lastCooldown = ONE_DAY;
      const lastDepositTime = blockTime - ONE_HOUR * 23 - ONE_MINUTE * 59;
      const calculated = (
        await poolLogicProxy.calculateCooldown(
          currentBalance,
          liquidityMinted,
          newCooldown,
          lastCooldown,
          lastDepositTime,
          blockTime,
        )
      ).toNumber();
      expect(calculated).to.equal(300);
      expect(calculated).to.be.greaterThan(calcRemainingCooldown(lastCooldown, lastDepositTime, blockTime));
    });

    it("should return additional cooldown when subsequent smaller deposit with reduced latest cooldown after cooldown", async () => {
      const currentBalance = 1000;
      const liquidityMinted = 100;
      const newCooldown = ONE_DAY;
      const blockTime = await getBlockTime();
      const lastCooldown = ONE_HOUR * 10;
      const lastDepositTime = blockTime - ONE_DAY * 42;
      const calculated = (
        await poolLogicProxy.calculateCooldown(
          currentBalance,
          liquidityMinted,
          newCooldown,
          lastCooldown,
          lastDepositTime,
          blockTime,
        )
      ).toNumber();
      expect(calculated).to.equal(8640);
      expect(calculated).to.be.greaterThan(calcRemainingCooldown(lastCooldown, lastDepositTime, blockTime));
    });

    it("should return remaining+additional cooldown when subsequent smaller deposit with reduced latest cooldown during cooldown", async () => {
      const currentBalance = 1000;
      const liquidityMinted = 10;
      const newCooldown = ONE_DAY;
      const blockTime = await getBlockTime();
      const lastCooldown = ONE_HOUR * 10;
      const lastDepositTime = blockTime - ONE_HOUR;
      const calculated = (
        await poolLogicProxy.calculateCooldown(
          currentBalance,
          liquidityMinted,
          newCooldown,
          lastCooldown,
          lastDepositTime,
          blockTime,
        )
      ).toNumber();
      const remaining = calcRemainingCooldown(lastCooldown, lastDepositTime, blockTime);
      expect(calculated).to.equal(864 + remaining);
      expect(calculated).to.be.greaterThan(remaining);
    });

    it("should return remaining+additional cooldown when subsequent smaller deposit during same block", async () => {
      const currentBalance = 1000;
      const liquidityMinted = 10;
      const newCooldown = ONE_MINUTE * 5;
      const blockTime = await getBlockTime();
      const lastCooldown = ONE_SECOND * 3;
      const lastDepositTime = blockTime;
      const calculated = (
        await poolLogicProxy.calculateCooldown(
          currentBalance,
          liquidityMinted,
          newCooldown,
          lastCooldown,
          lastDepositTime,
          blockTime,
        )
      ).toNumber();
      const remaining = calcRemainingCooldown(lastCooldown, lastDepositTime, blockTime);
      expect(calculated).to.equal(3 + remaining);
      expect(calculated).to.be.greaterThan(remaining);
    });

    it("should return default cooldown when subsequent larger deposit during same block", async () => {
      const currentBalance = 1000;
      const liquidityMinted = 1001;
      const newCooldown = ONE_MINUTE * 5;
      const blockTime = await getBlockTime();
      const lastCooldown = ONE_SECOND * 3;
      const lastDepositTime = blockTime;
      const calculated = (
        await poolLogicProxy.calculateCooldown(
          currentBalance,
          liquidityMinted,
          newCooldown,
          lastCooldown,
          lastDepositTime,
          blockTime,
        )
      ).toNumber();
      const remaining = calcRemainingCooldown(lastCooldown, lastDepositTime, blockTime);
      expect(calculated).to.equal(300);
      expect(calculated).to.be.greaterThan(remaining);
    });

    it("should return 1 second cooldown instead of 0 when liquidity minted is much less then balance (24h cooldown)", async () => {
      const currentBalance = 100000;
      const liquidityMinted = 1;
      const newCooldown = ONE_DAY;
      const blockTime = await getBlockTime();
      const lastCooldown = ONE_SECOND;
      const lastDepositTime = blockTime - ONE_SECOND;
      const calculated = (
        await poolLogicProxy.calculateCooldown(
          currentBalance,
          liquidityMinted,
          newCooldown,
          lastCooldown,
          lastDepositTime,
          blockTime,
        )
      ).toNumber();
      expect(calculated).to.equal(1);
    });

    it("should return 1 second cooldown instead of 0 when liquidity minted is much less then balance (5min cooldown)", async () => {
      const currentBalance = 100000;
      const liquidityMinted = 1;
      const newCooldown = ONE_MINUTE * 5;
      const blockTime = await getBlockTime();
      const lastCooldown = ONE_SECOND;
      const lastDepositTime = blockTime - ONE_SECOND;
      const calculated = (
        await poolLogicProxy.calculateCooldown(
          currentBalance,
          liquidityMinted,
          newCooldown,
          lastCooldown,
          lastDepositTime,
          blockTime,
        )
      ).toNumber();
      expect(calculated).to.equal(1);
    });
  });

  describe("exit cooldown after pool deposit works as intended", () => {
    const customCooldown = ONE_MINUTE * 5;

    it("can call depositForWithCustomCooldown only if whitelisted", async () => {
      expect(await poolFactory.customCooldownWhitelist(managerAddress)).to.equal(false);
      await expect(
        poolLogicProxy
          .connect(manager)
          .depositForWithCustomCooldown(investorAddress, usdcAddress, amount, customCooldown),
      ).to.be.revertedWith("only whitelisted sender");
      await poolFactory.addCustomCooldownWhitelist(managerAddress);
      expect(await poolFactory.customCooldownWhitelist(managerAddress)).to.equal(true);
      await poolLogicProxy
        .connect(manager)
        .depositForWithCustomCooldown(investorAddress, usdcAddress, amount, customCooldown);
      await poolFactory.removeCustomCooldownWhitelist(managerAddress);
      expect(await poolFactory.customCooldownWhitelist(managerAddress)).to.equal(false);
    });

    it("returns default exit cooldown after first deposit through depositFor", async () => {
      expect(await poolLogicProxy.getExitRemainingCooldown(investorAddress)).to.equal(0);
      await poolLogicProxy.depositFor(investorAddress, usdcAddress, amount);
      expect(await poolLogicProxy.getExitRemainingCooldown(investorAddress)).to.equal(86400);
    });

    it("returns custom exit cooldown after first deposit through depositForWithCustomCooldown", async () => {
      expect(await poolLogicProxy.getExitRemainingCooldown(investorAddress)).to.equal(0);
      await poolFactory.addCustomCooldownWhitelist(managerAddress);
      await poolLogicProxy
        .connect(manager)
        .depositForWithCustomCooldown(investorAddress, usdcAddress, amount, customCooldown);
      expect(await poolLogicProxy.getExitRemainingCooldown(investorAddress)).to.equal(customCooldown);
      await poolFactory.removeCustomCooldownWhitelist(managerAddress);
    });
  });
});
