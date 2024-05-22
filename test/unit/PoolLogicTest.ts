import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { ethers, upgrades } from "hardhat";

import { updateChainlinkAggregators } from "../testHelpers";
import { MockContract, PoolFactory, PoolLogic, PoolManagerLogic__factory, TestUSDC, TestWETH } from "../../types";
import { Contract, BigNumber } from "ethers";

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
  let manager: SignerWithAddress, investor: SignerWithAddress, dao: SignerWithAddress, user1: SignerWithAddress;
  let poolFactory: PoolFactory;
  let poolLogicProxy: PoolLogic;
  let weth: TestWETH, wethPriceFeed: MockContract;
  let wethAddress: string;
  let usdcProxy: TestUSDC, usdcPriceFeed: MockContract, linkPriceFeed: MockContract;
  let usdcAddress: string, managerAddress: string, investorAddress: string;
  let assetHandler: Contract;

  beforeEach(async () => {
    [manager, investor, dao, user1] = await ethers.getSigners();
    managerAddress = manager.address;
    investorAddress = investor.address;

    const TestUSDC = await ethers.getContractFactory("TestUSDC");
    usdcProxy = await TestUSDC.deploy(20000000);
    await usdcProxy.deployed();
    usdcAddress = usdcProxy.address;
    const MockContract = await ethers.getContractFactory("MockContract");
    usdcPriceFeed = await MockContract.deploy();
    const TestWETH = await ethers.getContractFactory("TestWETH");
    weth = await TestWETH.deploy(2_000_000);
    await weth.deployed();
    wethAddress = weth.address;
    wethPriceFeed = await MockContract.deploy();

    const PoolLogic = await ethers.getContractFactory("PoolLogic");
    const poolLogic = await PoolLogic.deploy();

    const PoolManagerLogic = await ethers.getContractFactory("PoolManagerLogic");
    const poolManagerLogic = await PoolManagerLogic.deploy();

    const AssetHandlerLogic = await ethers.getContractFactory(
      "contracts/priceAggregators/AssetHandler.sol:AssetHandler",
    );
    const assetHandlerInitAssets = [
      { asset: usdcAddress, assetType: 0, aggregator: usdcPriceFeed.address },
      { asset: wethAddress, assetType: 0, aggregator: wethPriceFeed.address },
    ];
    assetHandler = await upgrades.deployProxy(AssetHandlerLogic, [assetHandlerInitAssets]);
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
      { asset: wethAddress, isDeposit: true },
    ]);
    const pools = await poolFactory.getDeployedFunds();
    poolLogicProxy = PoolLogic.attach(pools[0]);

    linkPriceFeed = await MockContract.deploy();
    await updateChainlinkAggregators(usdcPriceFeed, wethPriceFeed, linkPriceFeed);

    await usdcProxy.connect(manager).approve(poolLogicProxy.address, 2000000e6);

    await usdcProxy.transfer(investor.address, 1000000e6);
    await usdcProxy.connect(investor).approve(poolLogicProxy.address, 1000000e6);
    await usdcProxy.transfer(user1.address, 1000000e6);
    await usdcProxy.connect(user1).approve(poolLogicProxy.address, 1000000e6);

    await weth.connect(manager).approve(poolLogicProxy.address, ethers.utils.parseUnits("100", 18));
    await weth.connect(manager).transfer(investor.address, ethers.utils.parseUnits("100", 18));
    await weth.connect(investor).approve(poolLogicProxy.address, ethers.utils.parseUnits("100", 18));
    await weth.connect(manager).transfer(user1.address, ethers.utils.parseUnits("100", 18));
    await weth.connect(user1).approve(poolLogicProxy.address, ethers.utils.parseUnits("100", 18));
  });

  // Replicating the 2nd way of attack mentioned in the following blog.
  // https://mixbytes.io/blog/overview-of-the-inflation-attack
  describe("Inflation attack mitigation", () => {
    it("doesn't allow manager to steal first investor's funds from the pool", async () => {
      const beforeAttack = await usdcProxy.connect(manager).balanceOf(manager.address);
      // pool manager deposits 10 usdc
      await poolLogicProxy.connect(manager).deposit(usdcAddress, 10e6);
      let sharesForManager = await poolLogicProxy.balanceOf(manager.address);
      await ethers.provider.send("evm_increaseTime", [86400]);
      await ethers.provider.send("evm_mine", []);
      // manager withdraws almost all shares except 100_000
      await poolLogicProxy.connect(manager).withdraw(sharesForManager.sub(100_000));
      sharesForManager = await poolLogicProxy.balanceOf(manager.address);

      // manager transfers 1_000_001e6 usdc to the poolLogicProxy directly
      await usdcProxy.connect(manager).transfer(poolLogicProxy.address, 1_000_001e6, { from: manager.address });
      // investor tries to deposit 10e6 usdc
      await expect(poolLogicProxy.connect(investor).deposit(usdcAddress, 10e6)).to.be.revertedWith(
        "invalid liquidityMinted",
      );
      const sharesForInvestor = await poolLogicProxy.balanceOf(investor.address);

      expect(sharesForInvestor).to.equal(0);

      // manager redeems all of his shares.
      await poolLogicProxy.connect(manager).withdraw(100_000);
      const afterAttack = await usdcProxy.connect(manager).balanceOf(manager.address);
      expect(beforeAttack).to.equal(afterAttack);
    });

    it("should revert if depositing tokens such that liquidity minted is below 100_000", async () => {
      // Manager tries to deposit 1 wei. This should mint 2000 shares.
      // Since the expected mint amount is less than < 100_000. This should revert.
      await expect(poolLogicProxy.connect(manager).deposit(wethAddress, 1)).to.be.revertedWith(
        "invalid liquidityMinted",
      );
    });

    it("loss of tokens due to inflation attack should be within acceptable range of 0.00001% (18 decimal tokens)", async () => {
      const investorBalanceBefore = await weth.balanceOf(investor.address);
      const userBalanceBefore = await weth.balanceOf(user1.address);

      // pool manager deposits 100 wei
      await poolLogicProxy.connect(manager).deposit(wethAddress, 100);
      let sharesForManager = await poolLogicProxy.balanceOf(manager.address);

      // Skipping ahead by 1 day.
      await ethers.provider.send("evm_increaseTime", [86400]);
      await ethers.provider.send("evm_mine", []);

      await poolLogicProxy.connect(manager).withdraw(sharesForManager.sub(100_000));
      sharesForManager = await poolLogicProxy.balanceOf(manager.address);

      // manager transfers 5e15 wei (0.005 eth) to the poolLogicProxy directly
      await weth
        .connect(manager)
        .transfer(poolLogicProxy.address, ethers.utils.parseUnits("5", 15), { from: manager.address });

      // investors deposit 1e16 wei (0.01 eth)
      await poolLogicProxy.connect(investor).deposit(wethAddress, ethers.utils.parseUnits("1", 16));
      await poolLogicProxy.connect(user1).deposit(wethAddress, ethers.utils.parseUnits("1", 16));
      const sharesForInvestor = await poolLogicProxy.balanceOf(investor.address);
      const sharesForUser = await poolLogicProxy.balanceOf(user1.address);

      await ethers.provider.send("evm_increaseTime", [86400]);
      await ethers.provider.send("evm_mine", []);

      // Setting a high value for chainlink timeout just for this test.
      await assetHandler.setChainlinkTimeout(900000);

      // manager withdraws all tokens before investor.
      await poolLogicProxy.connect(manager).withdraw(sharesForManager);

      // investors withdraw their shares of tokens.
      await poolLogicProxy.connect(investor).withdraw(sharesForInvestor);
      await poolLogicProxy.connect(user1).withdraw(sharesForUser);

      const investorBalanceAfter = await weth.balanceOf(investor.address);
      const userBalanceAfter = await weth.balanceOf(user1.address);

      // console.log("Investor balance after: ", investorBalanceAfter.toString());
      // console.log("User balance after: ", userBalanceAfter.toString());
      // console.log("Manager balance after: ", await weth.balanceOf(manager.address));

      // Accepting loss of 0.00001% due to the attack.
      // Note, higher the minSupply threshold, higher is the precision we can target (lower loss %).
      expect(investorBalanceAfter).to.be.gte(investorBalanceBefore.mul(9999).div(10000));
      expect(userBalanceAfter).to.be.gte(userBalanceBefore.mul(9999).div(10000));
    });

    it("should revert if withdrawing shares such that supply is below threshold of 100_000", async () => {
      // pool manager deposits 1 usdc
      await poolLogicProxy.connect(manager).deposit(usdcAddress, 1e6);
      const sharesForManager = await poolLogicProxy.balanceOf(manager.address);

      // Skipping ahead by 1 day.
      await ethers.provider.send("evm_increaseTime", [86400]);
      await ethers.provider.send("evm_mine", []);

      // Manager attempts to withdraw his portion of shares such that only 1 share remains.
      // This should fail as minimum share supply required in the pool is 100_000.
      await expect(poolLogicProxy.connect(manager).withdraw(sharesForManager.sub(1))).to.be.revertedWith(
        "below supply threshold",
      );
    });

    it("loss of tokens due to inflation attack should be within acceptable range of 0.00001% (6 decimal tokens)", async () => {
      const investorBalanceBefore = await usdcProxy.balanceOf(investor.address);
      const userBalanceBefore = await usdcProxy.balanceOf(user1.address);

      // pool manager deposits 1 usdc
      await poolLogicProxy.connect(manager).deposit(usdcAddress, 1e6);
      let sharesForManager = await poolLogicProxy.balanceOf(manager.address);

      // Skipping ahead by 1 day.
      await ethers.provider.send("evm_increaseTime", [86400]);
      await ethers.provider.send("evm_mine", []);

      await poolLogicProxy.connect(manager).withdraw(sharesForManager.sub(100_000));
      sharesForManager = await poolLogicProxy.balanceOf(manager.address);

      // manager transfers 501e6 usdc to the poolLogicProxy directly
      await usdcProxy.connect(manager).transfer(poolLogicProxy.address, 501e6, { from: manager.address });

      // investors deposit 1000e6 usdc
      await poolLogicProxy.connect(investor).deposit(usdcAddress, 1000e6);
      await poolLogicProxy.connect(user1).deposit(usdcAddress, 1000e6);
      const sharesForInvestor = await poolLogicProxy.balanceOf(investor.address);
      const sharesForUser = await poolLogicProxy.balanceOf(user1.address);

      await ethers.provider.send("evm_increaseTime", [86400]);
      await ethers.provider.send("evm_mine", []);

      // Setting a high value for chainlink timeout just for this test.
      await assetHandler.setChainlinkTimeout(900000);

      // manager withdraws all tokens before investor.
      await poolLogicProxy.connect(manager).withdraw(sharesForManager);

      // investors withdraw their shares of tokens.
      await poolLogicProxy.connect(investor).withdraw(sharesForInvestor);
      await poolLogicProxy.connect(user1).withdraw(sharesForUser);

      const investorBalanceAfter = await usdcProxy.balanceOf(investor.address);
      const userBalanceAfter = await usdcProxy.balanceOf(user1.address);

      // Accepting loss of 0.00001% due to the attack.
      // Note, higher the minSupply threshold, higher is the precision we can target (lower loss %).
      expect(investorBalanceAfter).to.be.gte(investorBalanceBefore.mul(9999).div(10000));
      expect(userBalanceAfter).to.be.gte(userBalanceBefore.mul(9999).div(10000));
    });
  });

  describe("Entry fee", () => {
    it("should account for entry fee when totalSupply is 0", async function () {
      const PoolManagerLogic = await ethers.getContractFactory("PoolManagerLogic");
      const poolManagerLogicAddr = await poolLogicProxy.poolManagerLogic();
      const poolManagerLogicProxy = PoolManagerLogic.attach(poolManagerLogicAddr);

      // refresh timestamp of Chainlink price round data
      await updateChainlinkAggregators(usdcPriceFeed, wethPriceFeed, linkPriceFeed);
      await assetHandler.setChainlinkTimeout(9000000);

      // Set the entry fee as 0.25%.
      await poolManagerLogicProxy.connect(manager).announceFeeIncrease(0, 0, 25);

      await ethers.provider.send("evm_increaseTime", [3600 * 24 * 7 * 4]); // add 4 weeks
      await poolManagerLogicProxy.connect(manager).commitFeeIncrease();

      await poolLogicProxy.connect(investor).deposit(usdcProxy.address, (100e6).toString());

      const sharesForInvestor = await poolLogicProxy.balanceOf(investorAddress);

      // This is equivalent of finding 99.75% of the liquidity minted for 100 USDC deposited.
      const expectedLiquidityMinted = BigNumber.from("9975").mul(BigNumber.from(10).pow(16));

      expect(sharesForInvestor).to.equal(expectedLiquidityMinted);
    });

    it("should account for entry fee when totalSupply is greater than 0", async function () {
      const PoolManagerLogic = await ethers.getContractFactory("PoolManagerLogic");
      const poolManagerLogicAddr = await poolLogicProxy.poolManagerLogic();
      const poolManagerLogicProxy = PoolManagerLogic.attach(poolManagerLogicAddr);

      // refresh timestamp of Chainlink price round data
      await updateChainlinkAggregators(usdcPriceFeed, wethPriceFeed, linkPriceFeed);
      await assetHandler.setChainlinkTimeout(9000000);

      // Set the entry fee as 0.25%.
      await poolManagerLogicProxy.connect(manager).announceFeeIncrease(0, 0, 25);

      await ethers.provider.send("evm_increaseTime", [3600 * 24 * 7 * 4]); // add 4 weeks
      await poolManagerLogicProxy.connect(manager).commitFeeIncrease();

      // Manager makes the first deposit.
      await poolLogicProxy.connect(manager).deposit(usdcProxy.address, (100e6).toString());
      const sharesForManager = await poolLogicProxy.balanceOf(managerAddress);

      await poolLogicProxy.connect(investor).deposit(usdcProxy.address, (100e6).toString());
      const sharesForInvestor = await poolLogicProxy.balanceOf(investorAddress);

      // This is equivalent of finding 99.75% of the liquidity minted for 100 USDC deposited.
      const expectedLiquidityMinted = BigNumber.from("9975").mul(BigNumber.from(10).pow(16));

      // The difference between the shares minted for the manager and investor should not differ by more than
      // 0.25%
      expect(sharesForInvestor).to.be.closeTo(expectedLiquidityMinted, expectedLiquidityMinted.mul(25).div(10_000));

      // The depositor who entered the pool earlier should have more number of shares.
      expect(sharesForInvestor).to.be.lt(sharesForManager);
    });
  });

  describe("receiverWhitelist", () => {
    it("cannot transfer tokens while under lockup", async () => {
      await poolLogicProxy.depositFor(investorAddress, usdcAddress, amount);
      expect(await poolLogicProxy.getExitRemainingCooldown(investorAddress)).to.equal(86400);
      await expect(
        poolLogicProxy.connect(investor).transfer(dao.address, await poolLogicProxy.balanceOf(investorAddress)),
      ).to.be.revertedWith("cooldown active");
    });

    it("can transfer tokens under lockup to addresses in receiverWhitelist", async () => {
      await poolLogicProxy.depositFor(investorAddress, usdcAddress, amount);
      expect(await poolLogicProxy.getExitRemainingCooldown(investorAddress)).to.equal(86400);
      await poolFactory.addReceiverWhitelist(dao.address);
      await poolLogicProxy.connect(investor).transfer(dao.address, await poolLogicProxy.balanceOf(investorAddress));
    });

    it("removing an address for receiverWhitelist stops it from being able to receive tokens under lockup", async () => {
      await poolLogicProxy.depositFor(investorAddress, usdcAddress, amount);
      expect(await poolLogicProxy.getExitRemainingCooldown(investorAddress)).to.equal(86400);
      await poolFactory.addReceiverWhitelist(dao.address);
      const balance = await poolLogicProxy.balanceOf(investorAddress);
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

  describe("private pool works as expected", () => {
    it("can't depositFor into private pool if recipient is not a member", async () => {
      await poolLogicProxy.connect(manager).setPoolPrivate(true);
      await expect(poolLogicProxy.connect(investor).depositFor(dao.address, usdcAddress, amount)).to.be.revertedWith(
        "only members allowed",
      );
      await expect(
        poolLogicProxy.connect(investor).depositFor(investor.address, usdcAddress, amount),
      ).to.be.revertedWith("only members allowed");
    });
    it("can't depositFor into private pool if recipient is not a member but caller is a member", async () => {
      await poolLogicProxy.connect(manager).setPoolPrivate(true);
      await expect(poolLogicProxy.connect(manager).depositFor(dao.address, usdcAddress, amount)).to.be.revertedWith(
        "only members allowed",
      );
    });
    it("can depositFor into private pool if recipient is a member", async () => {
      await poolLogicProxy.connect(manager).setPoolPrivate(true);
      await expect(
        poolLogicProxy.connect(investor).depositFor(investor.address, usdcAddress, amount),
      ).to.be.revertedWith("only members allowed");
      const poolManagerLogicProxy = PoolManagerLogic__factory.connect(await poolLogicProxy.poolManagerLogic(), manager);
      await poolManagerLogicProxy.connect(manager).addMember(investor.address);
      expect(await poolLogicProxy.balanceOf(investor.address)).to.equal(0);
      await poolLogicProxy.connect(investor).depositFor(investor.address, usdcAddress, amount);
      expect(await poolLogicProxy.balanceOf(investor.address)).not.to.equal(0);
    });
    it("can depositFor into private pool if recipient is a member, but caller is not a member", async () => {
      await poolLogicProxy.connect(manager).setPoolPrivate(true);
      const poolManagerLogicProxy = PoolManagerLogic__factory.connect(await poolLogicProxy.poolManagerLogic(), manager);
      await expect(poolLogicProxy.connect(investor).depositFor(dao.address, usdcAddress, amount)).to.be.revertedWith(
        "only members allowed",
      );
      await poolManagerLogicProxy.connect(manager).addMember(dao.address);
      expect(await poolLogicProxy.balanceOf(dao.address)).to.equal(0);
      await poolLogicProxy.connect(investor).depositFor(dao.address, usdcAddress, amount);
      expect(await poolLogicProxy.balanceOf(dao.address)).not.to.equal(0);
    });
  });

  describe("Specific pool pausing works as expected", () => {
    it("can pause and unpause pool", async () => {
      expect(await poolFactory.pausedPools(poolLogicProxy.address)).to.equal(false);
      await poolFactory.setPoolsPaused([{ pool: poolLogicProxy.address, paused: true }]);
      expect(await poolFactory.pausedPools(poolLogicProxy.address)).to.equal(true);
      await poolFactory.setPoolsPaused([{ pool: poolLogicProxy.address, paused: false }]);
      expect(await poolFactory.pausedPools(poolLogicProxy.address)).to.equal(false);
    });

    it("can't pause and unpause pool if not owner", async () => {
      await expect(
        poolFactory.connect(investor).setPoolsPaused([{ pool: poolLogicProxy.address, paused: true }]),
      ).to.be.revertedWith("caller is not the owner");
    });

    it("can't deposit into paused pool", async () => {
      await poolFactory.setPoolsPaused([{ pool: poolLogicProxy.address, paused: true }]);
      await expect(poolLogicProxy.connect(investor).deposit(usdcAddress, amount)).to.be.revertedWith("pool is paused");
      await expect(
        poolLogicProxy.connect(investor).depositFor(investor.address, usdcAddress, amount),
      ).to.be.revertedWith("pool is paused");
    });

    it("can't withdraw from paused pool", async () => {
      await poolFactory.setPoolsPaused([{ pool: poolLogicProxy.address, paused: true }]);
      await expect(poolLogicProxy.connect(investor).withdraw(amount)).to.be.revertedWith("pool is paused");
      await expect(poolLogicProxy.connect(investor).withdrawTo(investor.address, amount)).to.be.revertedWith(
        "pool is paused",
      );
    });

    it("can't mint fees in paused pool", async () => {
      await poolFactory.setPoolsPaused([{ pool: poolLogicProxy.address, paused: true }]);
      await expect(poolLogicProxy.mintManagerFee()).to.be.revertedWith("pool is paused");
    });
  });
});
