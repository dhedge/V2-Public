import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { ethers, upgrades } from "hardhat";

import { updateChainlinkAggregators } from "../../testHelpers";
import {
  MockContract,
  PoolFactory,
  PoolLogic,
  PoolLogicExposed,
  PoolManagerLogic__factory,
  TestUSDC,
  TestWETH,
  INonfungiblePositionManager__factory,
} from "../../../types";
import { Contract, BigNumber } from "ethers";
import { parseEther, parseUnits } from "ethers/lib/utils";

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
        "below threshold",
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

  describe("Fees", () => {
    describe("Entry fee", () => {
      it("should account for entry fee when totalSupply is 0", async function () {
        const PoolManagerLogic = await ethers.getContractFactory("PoolManagerLogic");
        const poolManagerLogicAddr = await poolLogicProxy.poolManagerLogic();
        const poolManagerLogicProxy = PoolManagerLogic.attach(poolManagerLogicAddr);

        // refresh timestamp of Chainlink price round data
        await updateChainlinkAggregators(usdcPriceFeed, wethPriceFeed, linkPriceFeed);
        await assetHandler.setChainlinkTimeout(9000000);

        // Set the entry fee as 0.25%.
        await poolManagerLogicProxy.connect(manager).announceFeeIncrease(0, 0, 25, 0);

        await ethers.provider.send("evm_increaseTime", [3600 * 24 * 7 * 4]); // add 4 weeks
        await poolManagerLogicProxy.connect(manager).commitFeeIncrease();

        const tokenPriceAtLastFeeMint = await poolLogicProxy.tokenPriceAtLastFeeMint();
        await poolLogicProxy.connect(investor).deposit(usdcProxy.address, (100e6).toString());

        const sharesForInvestor = await poolLogicProxy.balanceOf(investorAddress);
        const sharesForManager = await poolLogicProxy.balanceOf(managerAddress);

        // This is equivalent of finding 99.75% of the liquidity minted for 100 USDC deposited.
        const expectedLiquidityMinted = BigNumber.from("9975").mul(BigNumber.from(10).pow(16));
        const expectedManagerLiquidityMinted = BigNumber.from("25").mul(BigNumber.from(10).pow(16));
        const currentFundTokenPrice = await poolLogicProxy.tokenPrice();

        expect(sharesForInvestor).to.equal(expectedLiquidityMinted, "Investor shares incorrect");
        expect(sharesForManager).to.equal(expectedManagerLiquidityMinted, "Manager entry fee shares incorrect");
        expect(sharesForInvestor.mul(currentFundTokenPrice).div(parseUnits("1", 18))).to.equal(
          parseUnits("9975", 16), // $99.75
          "Manager entry fee shares incorrect in $ terms",
        );
        expect(sharesForManager.mul(currentFundTokenPrice).div(parseUnits("1", 18))).to.equal(
          parseUnits("25", 16), // $0.25
          "Manager entry fee shares incorrect in $ terms",
        );
        expect(currentFundTokenPrice).to.equal(tokenPriceAtLastFeeMint, "Fund token price should not change");
      });

      it("should account for entry fee when totalSupply is greater than 0", async function () {
        const PoolManagerLogic = await ethers.getContractFactory("PoolManagerLogic");
        const poolManagerLogicAddr = await poolLogicProxy.poolManagerLogic();
        const poolManagerLogicProxy = PoolManagerLogic.attach(poolManagerLogicAddr);

        // refresh timestamp of Chainlink price round data
        await updateChainlinkAggregators(usdcPriceFeed, wethPriceFeed, linkPriceFeed);
        await assetHandler.setChainlinkTimeout(9000000);

        // Set the entry fee as 0.25%.
        await poolManagerLogicProxy.connect(manager).announceFeeIncrease(0, 0, 25, 0);

        await ethers.provider.send("evm_increaseTime", [3600 * 24 * 7 * 4]); // add 4 weeks
        await poolManagerLogicProxy.connect(manager).commitFeeIncrease();

        const tokenPriceAtLastFeeMint = await poolLogicProxy.tokenPriceAtLastFeeMint();

        // Manager makes the first deposit.
        await poolLogicProxy.connect(manager).deposit(usdcProxy.address, (100e6).toString());
        const sharesForManager = await poolLogicProxy.balanceOf(managerAddress);

        expect(await poolLogicProxy.tokenPrice()).to.equal(
          tokenPriceAtLastFeeMint,
          "Fund token price should not change (after first deposit)",
        );

        await poolLogicProxy.connect(investor).deposit(usdcProxy.address, (100e6).toString());
        const sharesForInvestor = await poolLogicProxy.balanceOf(investorAddress);

        // This is equivalent of finding 99.75% of the liquidity minted for 100 USDC deposited.
        const expectedLiquidityMinted = BigNumber.from("9975").mul(BigNumber.from(10).pow(16));
        const expectedManagerLiquidityMinted = BigNumber.from("10000").mul(BigNumber.from(10).pow(16));
        const currentFundTokenPrice = await poolLogicProxy.tokenPrice();

        expect(sharesForInvestor).to.equal(expectedLiquidityMinted, "Investor shares incorrect");
        expect(sharesForManager).to.equal(
          expectedManagerLiquidityMinted,
          "Manager shares shouldn't be impacted by fees",
        );
        expect(sharesForInvestor.mul(currentFundTokenPrice).div(parseUnits("1", 18))).to.equal(
          parseUnits("9975", 16), // $99.75
          "Investor shares incorrect in $ terms",
        );
        expect(sharesForManager.mul(currentFundTokenPrice).div(parseUnits("1", 18))).to.equal(
          parseUnits("10000", 16), // $100
          "Manager shares incorrect in $ terms",
        );
        expect(currentFundTokenPrice).to.equal(
          tokenPriceAtLastFeeMint,
          "Fund token price should not change (after all deposits)",
        );
      });
    });

    describe("Exit fee", () => {
      it("should account for exit fee when when single asset in pool", async function () {
        const PoolManagerLogic = await ethers.getContractFactory("PoolManagerLogic");
        const poolManagerLogicAddr = await poolLogicProxy.poolManagerLogic();
        const poolManagerLogicProxy = PoolManagerLogic.attach(poolManagerLogicAddr);

        const defaultUSDCDepositAmount = BigNumber.from(100e6);

        // refresh timestamp of Chainlink price round data
        await updateChainlinkAggregators(usdcPriceFeed, wethPriceFeed, linkPriceFeed);
        await assetHandler.setChainlinkTimeout(9000000);

        // Set the exit fee as 0.25%.
        await poolManagerLogicProxy.connect(manager).announceFeeIncrease(0, 0, 0, 25);

        // Manager makes the first deposit.
        await poolLogicProxy.connect(manager).deposit(usdcProxy.address, defaultUSDCDepositAmount);

        await ethers.provider.send("evm_increaseTime", [3600 * 24 * 7 * 4]); // add 4 weeks
        await poolManagerLogicProxy.connect(manager).commitFeeIncrease();

        const investorBalanceBefore = await usdcProxy.balanceOf(investorAddress);

        await poolLogicProxy.connect(investor).deposit(usdcProxy.address, defaultUSDCDepositAmount);
        const sharesForInvestor = await poolLogicProxy.balanceOf(investorAddress);

        await ethers.provider.send("evm_increaseTime", [3600 * 24]); // add 24 hours

        const managerBalanceBeforeExitFee = await poolLogicProxy.balanceOf(managerAddress);
        const fundTokenPricePreExit = await poolLogicProxy.tokenPrice();

        // Redeem all shares of the investor.
        await poolLogicProxy.connect(investor).withdraw(sharesForInvestor);

        const managerBalanceAfterExitFee = await poolLogicProxy.balanceOf(managerAddress);
        const investorBalanceAfterRedemption = await usdcProxy.balanceOf(investorAddress);

        // The difference between the balance of the manager before and after the exit fee should be
        // 0.25% of the total amount redeemed (in vault share terms).
        const expectedExitFeeVaultShares = BigNumber.from("25").mul(sharesForInvestor).div("10000");

        // For the investor, the difference between the balance before and after the exit fee should be
        // 0.25% of the total amount redeemed (in USDC terms).
        const expectedExitFeeUSDC = BigNumber.from("25").mul(defaultUSDCDepositAmount).div("10000");

        expect(managerBalanceAfterExitFee).to.equal(managerBalanceBeforeExitFee.add(expectedExitFeeVaultShares));
        expect(investorBalanceAfterRedemption).to.equal(investorBalanceBefore.sub(expectedExitFeeUSDC));
        expect(await poolLogicProxy.tokenPrice()).to.equal(fundTokenPricePreExit);
      });

      it("should account for exit fee when multiple assets in pool", async function () {
        const PoolManagerLogic = await ethers.getContractFactory("PoolManagerLogic");
        const poolManagerLogicAddr = await poolLogicProxy.poolManagerLogic();
        const poolManagerLogicProxy = PoolManagerLogic.attach(poolManagerLogicAddr);

        const defaultUSDCDepositAmount = BigNumber.from(100e6);
        const defaultWETHDepositAmount = ethers.utils.parseUnits("1", 18);

        // refresh timestamp of Chainlink price round data
        await updateChainlinkAggregators(usdcPriceFeed, wethPriceFeed, linkPriceFeed);
        await assetHandler.setChainlinkTimeout(9000000);

        // Set the exit fee as 0.25%.
        await poolManagerLogicProxy.connect(manager).announceFeeIncrease(0, 0, 0, 25);

        // Manager makes the first deposit.
        await poolLogicProxy.connect(manager).deposit(usdcProxy.address, defaultUSDCDepositAmount);
        await poolLogicProxy.connect(manager).deposit(weth.address, defaultWETHDepositAmount);

        await ethers.provider.send("evm_increaseTime", [3600 * 24 * 7 * 4]); // add 4 weeks
        await poolManagerLogicProxy.connect(manager).commitFeeIncrease();

        const investorUSDCBalanceBefore = await usdcProxy.balanceOf(investorAddress);
        const investorWETHBalanceBefore = await weth.balanceOf(investorAddress);

        await poolLogicProxy.connect(investor).deposit(usdcProxy.address, defaultUSDCDepositAmount);
        await poolLogicProxy.connect(investor).deposit(weth.address, defaultWETHDepositAmount);
        const sharesForInvestor = await poolLogicProxy.balanceOf(investorAddress);

        await ethers.provider.send("evm_increaseTime", [3600 * 24]); // add 24 hours

        const managerBalanceBeforeExitFee = await poolLogicProxy.balanceOf(managerAddress);
        const fundTokenPricePreExit = await poolLogicProxy.tokenPrice();

        // Redeem all shares of the investor.
        await poolLogicProxy.connect(investor).withdraw(sharesForInvestor);

        const managerBalanceAfterExitFee = await poolLogicProxy.balanceOf(managerAddress);
        const investorUSDCBalanceAfterRedemption = await usdcProxy.balanceOf(investorAddress);
        const investorWETHBalanceAfterRedemption = await weth.balanceOf(investorAddress);

        // The difference between the balance of the manager before and after the exit fee should be
        // 0.25% of the total amount redeemed (in vault share terms).
        const expectedExitFeeVaultShares = BigNumber.from("25").mul(sharesForInvestor).div("10000");

        // The difference between the balance of the investor before and after the exit fee should be
        // 0.25% of the total amount redeemed (in underlying asset terms).
        const expectedUSDCExitFee = BigNumber.from("25").mul(defaultUSDCDepositAmount).div("10000");
        const expectedWETHExitFee = BigNumber.from("25").mul(defaultWETHDepositAmount).div("10000");

        expect(managerBalanceAfterExitFee).to.equal(managerBalanceBeforeExitFee.add(expectedExitFeeVaultShares));
        expect(investorUSDCBalanceAfterRedemption).to.equal(investorUSDCBalanceBefore.sub(expectedUSDCExitFee));
        expect(investorWETHBalanceAfterRedemption).to.equal(investorWETHBalanceBefore.sub(expectedWETHExitFee));
        expect(await poolLogicProxy.tokenPrice()).to.equal(fundTokenPricePreExit);
      });
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

  describe("tokenPriceAtLastFeeMint", () => {
    it("should reset tokenPriceAtLastFeeMint to 1e18 after full withdrawal", async () => {
      // refresh timestamp of Chainlink price round data
      await updateChainlinkAggregators(usdcPriceFeed, wethPriceFeed, linkPriceFeed);
      await assetHandler.setChainlinkTimeout(9000000);

      await poolLogicProxy.depositFor(investorAddress, usdcAddress, amount);
      const tokenPriceAfterDeposit = await poolLogicProxy.tokenPrice();

      // Increase the fund token price by direct deposit.
      await usdcProxy.connect(manager).transfer(poolLogicProxy.address, 100e6);

      expect(await poolLogicProxy.tokenPrice()).to.be.gt(tokenPriceAfterDeposit);

      await ethers.provider.send("evm_increaseTime", [3600 * 25]); // add 25 hours
      await poolLogicProxy.connect(manager).mintManagerFee();

      expect(await poolLogicProxy.tokenPriceAtLastFeeMint()).to.be.gt(parseUnits("1", 18));

      // Withdraw all the funds.
      await poolLogicProxy.connect(investor).withdraw(await poolLogicProxy.balanceOf(investorAddress));

      expect(await poolLogicProxy.tokenPrice()).to.equal(0);
      expect(await poolLogicProxy.tokenPriceAtLastFeeMint()).to.equal(parseUnits("1", 18));
    });
  });

  describe("lastFeeMintTime", () => {
    it("shouldn't change if streaming fee < 0", async () => {
      const PoolManagerLogic = await ethers.getContractFactory("PoolManagerLogic");
      const poolManagerLogicAddr = await poolLogicProxy.poolManagerLogic();
      const poolManagerLogicProxy = PoolManagerLogic.attach(poolManagerLogicAddr);

      // refresh timestamp of Chainlink price round data
      await updateChainlinkAggregators(usdcPriceFeed, wethPriceFeed, linkPriceFeed);
      await assetHandler.setChainlinkTimeout(9000000);

      // Set the streaming fee as 3%.
      await poolManagerLogicProxy.connect(manager).announceFeeIncrease(0, 300, 0, 0);

      await ethers.provider.send("evm_increaseTime", [3600 * 24 * 7 * 4]); // add 4 weeks
      await poolManagerLogicProxy.connect(manager).commitFeeIncrease();

      await poolLogicProxy.connect(investor).deposit(usdcProxy.address, (100e6).toString());

      const sharesForInvestor = await poolLogicProxy.balanceOf(investorAddress);

      await ethers.provider.send("evm_increaseTime", [3600 * 25]);
      await ethers.provider.send("evm_mine", []);

      const sharesToWithdraw = sharesForInvestor.sub(100_000);

      await poolLogicProxy.connect(investor).withdraw(sharesToWithdraw);

      // Since streaming fee portions go to the manager and the DAO, we first need to redeem the fee shares.
      // This way, we can get the total supply down to 100_000 shares.
      await poolLogicProxy.connect(dao).withdraw(await poolLogicProxy.balanceOf(dao.address));
      await poolLogicProxy.connect(manager).withdraw(await poolLogicProxy.balanceOf(manager.address));

      const feeMintTimeBeforeFinalWithdrawal = await poolLogicProxy.lastFeeMintTime();

      await poolLogicProxy.connect(investor).withdraw(100_000);

      expect(await poolLogicProxy.lastFeeMintTime()).to.equal(feeMintTimeBeforeFinalWithdrawal);
    });
  });

  describe("calculateCooldown calculates exit cooldown correctly", () => {
    let poolLogicExposed: PoolLogicExposed;

    before(async () => {
      const PoolLogicExposed = await ethers.getContractFactory("PoolLogicExposed");
      poolLogicExposed = await PoolLogicExposed.deploy();
    });

    it("should return default cooldown when subsequent larger deposit during early cooldown", async () => {
      const currentBalance = 100;
      const liquidityMinted = currentBalance * 4;
      const newCooldown = ONE_DAY;
      const blockTime = await getBlockTime();
      const lastCooldown = ONE_DAY;
      const lastDepositTime = blockTime - ONE_MINUTE - ONE_SECOND;
      const calculated = (
        await poolLogicExposed._calculateCooldownExposed(
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
        await poolLogicExposed._calculateCooldownExposed(
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
        await poolLogicExposed._calculateCooldownExposed(
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
        await poolLogicExposed._calculateCooldownExposed(
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
        await poolLogicExposed._calculateCooldownExposed(
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
        await poolLogicExposed._calculateCooldownExposed(
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
        await poolLogicExposed._calculateCooldownExposed(
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
        await poolLogicExposed._calculateCooldownExposed(
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
        await poolLogicExposed._calculateCooldownExposed(
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
        await poolLogicExposed._calculateCooldownExposed(
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
        await poolLogicExposed._calculateCooldownExposed(
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
        await poolLogicExposed._calculateCooldownExposed(
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
        await poolLogicExposed._calculateCooldownExposed(
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
        await poolLogicExposed._calculateCooldownExposed(
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
        await poolLogicExposed._calculateCooldownExposed(
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
        await poolLogicExposed._calculateCooldownExposed(
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
        await poolLogicExposed._calculateCooldownExposed(
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
        await poolLogicExposed._calculateCooldownExposed(
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
        await poolLogicExposed._calculateCooldownExposed(
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
        await poolLogicExposed._calculateCooldownExposed(
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
        await poolLogicExposed._calculateCooldownExposed(
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
        await poolLogicExposed._calculateCooldownExposed(
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
        await poolLogicExposed._calculateCooldownExposed(
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
        await poolLogicExposed._calculateCooldownExposed(
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
        await poolLogicExposed._calculateCooldownExposed(
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
        await poolLogicExposed._calculateCooldownExposed(
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
      ).to.be.revertedWith("only allowed");
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
        "only members",
      );
      await expect(
        poolLogicProxy.connect(investor).depositFor(investor.address, usdcAddress, amount),
      ).to.be.revertedWith("only members");
    });
    it("can't depositFor into private pool if recipient is not a member but caller is a member", async () => {
      await poolLogicProxy.connect(manager).setPoolPrivate(true);
      await expect(poolLogicProxy.connect(manager).depositFor(dao.address, usdcAddress, amount)).to.be.revertedWith(
        "only members",
      );
    });
    it("can depositFor into private pool if recipient is a member", async () => {
      await poolLogicProxy.connect(manager).setPoolPrivate(true);
      await expect(
        poolLogicProxy.connect(investor).depositFor(investor.address, usdcAddress, amount),
      ).to.be.revertedWith("only members");
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
        "only members",
      );
      await poolManagerLogicProxy.connect(manager).addMember(dao.address);
      expect(await poolLogicProxy.balanceOf(dao.address)).to.equal(0);
      await poolLogicProxy.connect(investor).depositFor(dao.address, usdcAddress, amount);
      expect(await poolLogicProxy.balanceOf(dao.address)).not.to.equal(0);
    });

    it("can deposit if the depositor is the manager and pool is private", async () => {
      await poolLogicProxy.connect(manager).setPoolPrivate(true);
      await poolLogicProxy.connect(manager).deposit(usdcAddress, amount);

      expect(await poolLogicProxy.balanceOf(managerAddress)).to.be.gt(0);
    });

    it("can transfer private pool tokens to addresses which are allowed members", async () => {
      const PoolManagerLogic = await ethers.getContractFactory("PoolManagerLogic");
      const poolManagerLogicAddr = await poolLogicProxy.poolManagerLogic();
      const poolManagerLogicProxy = PoolManagerLogic.attach(poolManagerLogicAddr);

      // Make an initial deposit without setting the pool private.
      await poolLogicProxy.depositFor(investorAddress, usdcAddress, amount);
      await ethers.provider.send("evm_increaseTime", [3600 * 25]); // add 25 hours

      await poolLogicProxy.connect(manager).setPoolPrivate(true);
      await poolManagerLogicProxy.connect(manager).addMember(user1.address);

      const amountToTransfer = (await poolLogicProxy.balanceOf(investorAddress)).div(2);
      await poolLogicProxy.connect(investor).transfer(user1.address, amountToTransfer);

      expect(await poolLogicProxy.balanceOf(user1.address)).to.equal(amountToTransfer);
    });

    it("can transfer private pool tokens to addresses not an allowed member (only mint whitelisting)", async () => {
      await poolLogicProxy.depositFor(investorAddress, usdcAddress, amount);
      await ethers.provider.send("evm_increaseTime", [3600 * 25]); // add 25 hours

      await poolLogicProxy.connect(manager).setPoolPrivate(true);

      const amountToTransfer = (await poolLogicProxy.balanceOf(investorAddress)).div(2);
      await poolLogicProxy.connect(investor).transfer(user1.address, amountToTransfer);

      expect(await poolLogicProxy.balanceOf(user1.address)).to.equal(amountToTransfer);
    });

    it("can withdraw if member is not allowed but had private pool tokens before pool was set to private", async () => {
      const usdcBalanceBefore = await usdcProxy.balanceOf(investorAddress);
      await poolLogicProxy.depositFor(investorAddress, usdcAddress, amount);
      await ethers.provider.send("evm_increaseTime", [3600 * 25]); // add 25 hours

      await poolLogicProxy.connect(manager).setPoolPrivate(true);

      // refresh timestamp of Chainlink price round data
      await updateChainlinkAggregators(usdcPriceFeed, wethPriceFeed, linkPriceFeed);
      await assetHandler.setChainlinkTimeout(9000000);

      await poolLogicProxy.connect(investor).withdraw(await poolLogicProxy.balanceOf(investorAddress));

      expect(await poolLogicProxy.balanceOf(investorAddress)).to.equal(0);
      expect(await usdcProxy.balanceOf(investorAddress)).to.be.gt(usdcBalanceBefore);
    });

    it("can withdraw if member is not allowed but had private pool tokens before pool was set to private (fees set)", async () => {
      const PoolManagerLogic = await ethers.getContractFactory("PoolManagerLogic");
      const poolManagerLogicAddr = await poolLogicProxy.poolManagerLogic();
      const poolManagerLogicProxy = PoolManagerLogic.attach(poolManagerLogicAddr);

      // refresh timestamp of Chainlink price round data
      await updateChainlinkAggregators(usdcPriceFeed, wethPriceFeed, linkPriceFeed);
      await assetHandler.setChainlinkTimeout(9000000);

      // Set the entry fee as 0.25% and manager fee to 3%.
      await poolManagerLogicProxy.connect(manager).announceFeeIncrease(0, 300, 25, 0);

      await ethers.provider.send("evm_increaseTime", [3600 * 24 * 7 * 4]); // add 4 weeks
      await poolManagerLogicProxy.connect(manager).commitFeeIncrease();

      await poolLogicProxy.connect(investor).deposit(usdcAddress, amount);
      await ethers.provider.send("evm_increaseTime", [3600 * 25]); // add 25 hours

      await poolLogicProxy.connect(manager).setPoolPrivate(true);

      await poolLogicProxy.connect(investor).withdraw(await poolLogicProxy.balanceOf(investorAddress));

      expect(await poolLogicProxy.balanceOf(investorAddress)).to.equal(0);
    });

    it("Manager and DAO should be able to withdraw fees after pool is set to private", async () => {
      const PoolManagerLogic = await ethers.getContractFactory("PoolManagerLogic");
      const poolManagerLogicAddr = await poolLogicProxy.poolManagerLogic();
      const poolManagerLogicProxy = PoolManagerLogic.attach(poolManagerLogicAddr);

      // refresh timestamp of Chainlink price round data
      await updateChainlinkAggregators(usdcPriceFeed, wethPriceFeed, linkPriceFeed);
      await assetHandler.setChainlinkTimeout(9000000);

      // Set the entry fee as 0.25% and manager fee to 3%.
      await poolManagerLogicProxy.connect(manager).announceFeeIncrease(0, 300, 25, 0);

      await ethers.provider.send("evm_increaseTime", [3600 * 24 * 7 * 4]); // add 4 weeks
      await poolManagerLogicProxy.connect(manager).commitFeeIncrease();

      const managerUSDCBalanceBefore = await usdcProxy.balanceOf(managerAddress);
      const daoUSDCBalanceBefore = await usdcProxy.balanceOf(dao.address);

      await poolLogicProxy.connect(investor).deposit(usdcAddress, amount);
      await ethers.provider.send("evm_increaseTime", [3600 * 25]); // add 25 hours

      await poolLogicProxy.connect(manager).setPoolPrivate(true);

      // Manager should be able to reedem the fees after the pool is set to private.
      await poolLogicProxy.connect(manager).withdraw(await poolLogicProxy.balanceOf(managerAddress));
      await poolLogicProxy.connect(dao).withdraw(await poolLogicProxy.balanceOf(dao.address));

      expect(await usdcProxy.balanceOf(managerAddress)).to.be.gt(managerUSDCBalanceBefore);
      expect(await usdcProxy.balanceOf(dao.address)).to.be.gt(daoUSDCBalanceBefore);
    });

    it("cannot transfer to 0 address after setting pool as private", async () => {
      await poolLogicProxy.depositFor(investorAddress, usdcAddress, amount);

      await poolLogicProxy.connect(manager).setPoolPrivate(true);
      await ethers.provider.send("evm_increaseTime", [3600 * 25]); // add 25 hours

      const amountToTransfer = (await poolLogicProxy.balanceOf(investorAddress)).div(2);

      await expect(
        poolLogicProxy.connect(investor).transfer(ethers.constants.AddressZero, amountToTransfer),
      ).to.be.revertedWith("ERC20: transfer to the zero address");
    });
  });

  describe("Specific pool pausing works as expected", () => {
    it("can pause and unpause pool", async () => {
      expect(await poolFactory.pausedPools(poolLogicProxy.address)).to.equal(false);
      await poolFactory.setPoolsPaused([{ pool: poolLogicProxy.address, pauseShares: true, pauseTrading: false }]);
      expect(await poolFactory.pausedPools(poolLogicProxy.address)).to.equal(true);
      await poolFactory.setPoolsPaused([{ pool: poolLogicProxy.address, pauseShares: false, pauseTrading: false }]);
      expect(await poolFactory.pausedPools(poolLogicProxy.address)).to.equal(false);
    });

    it("can pause and unpause pool for trading", async () => {
      expect(await poolFactory.tradingPausedPools(poolLogicProxy.address)).to.equal(false);
      await poolFactory.setPoolsPaused([{ pool: poolLogicProxy.address, pauseShares: false, pauseTrading: true }]);
      expect(await poolFactory.tradingPausedPools(poolLogicProxy.address)).to.equal(true);
      await poolFactory.setPoolsPaused([{ pool: poolLogicProxy.address, pauseShares: false, pauseTrading: false }]);
      expect(await poolFactory.tradingPausedPools(poolLogicProxy.address)).to.equal(false);
    });

    it("can't pause and unpause pool if not owner", async () => {
      await expect(
        poolFactory
          .connect(investor)
          .setPoolsPaused([{ pool: poolLogicProxy.address, pauseShares: true, pauseTrading: false }]),
      ).to.be.revertedWith("Ownable: caller is not the owner");
    });

    it("can't deposit into paused pool", async () => {
      await poolFactory.setPoolsPaused([{ pool: poolLogicProxy.address, pauseShares: true, pauseTrading: false }]);
      await expect(poolLogicProxy.connect(investor).deposit(usdcAddress, amount)).to.be.revertedWith("pool paused");
      await expect(
        poolLogicProxy.connect(investor).depositFor(investor.address, usdcAddress, amount),
      ).to.be.revertedWith("pool paused");
    });

    it("can't withdraw from paused pool", async () => {
      await poolFactory.setPoolsPaused([{ pool: poolLogicProxy.address, pauseShares: true, pauseTrading: false }]);
      await expect(poolLogicProxy.connect(investor).withdraw(amount)).to.be.revertedWith("pool paused");
      await expect(poolLogicProxy.connect(investor).withdrawTo(investor.address, amount)).to.be.revertedWith(
        "pool paused",
      );
    });

    it("can't mint fees in paused pool", async () => {
      await poolFactory.setPoolsPaused([{ pool: poolLogicProxy.address, pauseShares: true, pauseTrading: false }]);
      await expect(poolLogicProxy.mintManagerFee()).to.be.revertedWith("pool paused");
    });

    it("can't transfer shares of paused pool", async () => {
      await poolFactory.setPoolsPaused([{ pool: poolLogicProxy.address, pauseShares: true, pauseTrading: false }]);
      await expect(poolLogicProxy.connect(investor).transfer(user1.address, amount)).to.be.revertedWith("pool paused");
    });

    it("can't transferFrom shares of paused pool", async () => {
      await poolFactory.setPoolsPaused([{ pool: poolLogicProxy.address, pauseShares: true, pauseTrading: false }]);
      await expect(
        poolLogicProxy.connect(investor).transferFrom(investorAddress, user1.address, amount),
      ).to.be.revertedWith("pool paused");
    });

    it("can trade in paused pool", async () => {
      await poolFactory.setPoolsPaused([{ pool: poolLogicProxy.address, pauseShares: true, pauseTrading: false }]);
      // Using mock data for execTransaction to make sure it doesn't revert on "trading paused"
      const someTxData = usdcProxy.interface.encodeFunctionData("transfer", [poolLogicProxy.address, amount]);
      await expect(poolLogicProxy.connect(manager).execTransaction(usdcAddress, someTxData)).to.be.revertedWith(
        "invalid transaction",
      );
    });

    it("can't trade in trading paused pool", async () => {
      await poolFactory.setPoolsPaused([{ pool: poolLogicProxy.address, pauseShares: false, pauseTrading: true }]);
      await expect(
        poolLogicProxy.connect(manager).execTransaction(ethers.constants.AddressZero, "0x"),
      ).to.be.revertedWith("trading paused");
      await expect(
        poolLogicProxy.connect(manager).execTransactions([{ to: ethers.constants.AddressZero, data: "0x" }]),
      ).to.be.revertedWith("trading paused");
    });

    it("can deposit into trading paused pool", async () => {
      await poolFactory.setPoolsPaused([{ pool: poolLogicProxy.address, pauseShares: false, pauseTrading: true }]);
      await poolLogicProxy.connect(investor).deposit(usdcAddress, amount);
      await poolLogicProxy.connect(investor).depositFor(investor.address, usdcAddress, amount);
    });

    it("can withdraw from trading paused pool", async () => {
      await assetHandler.setChainlinkTimeout(9000000);
      await poolLogicProxy.connect(investor).deposit(usdcAddress, amount);
      await ethers.provider.send("evm_increaseTime", [3600 * 25]); // add 25 hours

      await poolFactory.setPoolsPaused([{ pool: poolLogicProxy.address, pauseShares: false, pauseTrading: true }]);
      await poolLogicProxy.connect(investor).withdraw(amount);
      await poolLogicProxy.connect(investor).withdrawTo(investor.address, amount);
    });

    it("can mint fees in trading paused pool", async () => {
      await poolFactory.setPoolsPaused([{ pool: poolLogicProxy.address, pauseShares: false, pauseTrading: true }]);
      await poolLogicProxy.mintManagerFee();
    });

    it("can transfer shares of trading paused pool", async () => {
      await assetHandler.setChainlinkTimeout(9000000);
      await poolLogicProxy.connect(investor).deposit(usdcAddress, amount);
      await ethers.provider.send("evm_increaseTime", [3600 * 25]); // add 25 hours

      await poolFactory.setPoolsPaused([{ pool: poolLogicProxy.address, pauseShares: false, pauseTrading: true }]);
      await poolLogicProxy.connect(investor).transfer(user1.address, await poolLogicProxy.balanceOf(investorAddress));
    });

    it("can transferFrom shares of trading paused pool", async () => {
      await assetHandler.setChainlinkTimeout(9000000);
      await poolLogicProxy.connect(investor).deposit(usdcAddress, amount);
      await ethers.provider.send("evm_increaseTime", [3600 * 25]); // add 25 hours

      await poolFactory.setPoolsPaused([{ pool: poolLogicProxy.address, pauseShares: false, pauseTrading: true }]);
      await poolLogicProxy.connect(investor).approve(investorAddress, await poolLogicProxy.balanceOf(investorAddress));
      await poolLogicProxy
        .connect(investor)
        .transferFrom(investorAddress, user1.address, await poolLogicProxy.balanceOf(investorAddress));
    });
  });

  describe("NFT position deposit check", () => {
    it("shouldn't allow depositing position NFTs", async () => {
      const iPoolManagerLogic = new ethers.utils.Interface(PoolManagerLogic__factory.abi);
      const iNonfungiblePositionManager = new ethers.utils.Interface(INonfungiblePositionManager__factory.abi);
      const MockContract = await ethers.getContractFactory("MockContract");

      const nonfungiblePositionManagerMock = await MockContract.deploy();
      const poolManagerLogicMock = await MockContract.deploy();
      await nonfungiblePositionManagerMock.deployed();
      await poolManagerLogicMock.deployed();

      await poolLogicProxy.setPoolManagerLogic(poolManagerLogicMock.address);

      const id = parseUnits("1", 18);

      // Set mock calls.
      await poolManagerLogicMock.givenCalldataReturnBool(
        iPoolManagerLogic.encodeFunctionData("isDepositAsset", [nonfungiblePositionManagerMock.address]),
        true,
      );

      await nonfungiblePositionManagerMock.givenCalldataReturnBool(
        iNonfungiblePositionManager.encodeFunctionData("supportsInterface", [0x80ac58cd]),
        true,
      );

      await nonfungiblePositionManagerMock.givenCalldataReturnAddress(
        iNonfungiblePositionManager.encodeFunctionData("ownerOf", [id]),
        investorAddress,
      );

      await expect(
        poolLogicProxy.connect(investor).deposit(nonfungiblePositionManagerMock.address, id),
      ).to.be.revertedWith("NFTs not supported");
    });

    it("should allow WETH deposits", async () => {
      const TestWETH9 = await ethers.getContractFactory("WETH9");
      const weth9 = await TestWETH9.deploy();
      await weth9.deployed();

      assetHandler.addAsset(weth9.address, 0, wethPriceFeed.address);

      const PoolManagerLogic = await ethers.getContractFactory("PoolManagerLogic");
      const poolManagerLogic = PoolManagerLogic.attach(await poolLogicProxy.poolManagerLogic());

      await poolManagerLogic.connect(manager).changeAssets([{ asset: weth9.address, isDeposit: true }], []);

      await weth9.connect(investor).deposit({ value: parseEther("1") });

      await weth9.connect(investor).approve(poolLogicProxy.address, parseEther("1"));
      await poolLogicProxy.connect(investor).deposit(weth9.address, parseEther("1"));

      expect(await weth9.balanceOf(poolLogicProxy.address)).to.equal(parseEther("1"));
    });

    it("should allow deposit of assets with non-view fallback functions", async () => {
      const TestFallbackAsset = await ethers.getContractFactory("TestAssetWithFallback");
      const asset = await TestFallbackAsset.deploy(2_000_000);
      await asset.deployed();

      // Doesn't matter which price feed we use here.
      assetHandler.addAsset(asset.address, 0, usdcPriceFeed.address);

      const PoolManagerLogic = await ethers.getContractFactory("PoolManagerLogic");
      const poolManagerLogic = PoolManagerLogic.attach(await poolLogicProxy.poolManagerLogic());

      await poolManagerLogic.connect(manager).changeAssets([{ asset: asset.address, isDeposit: true }], []);

      await asset.connect(manager).mint(investor.address, parseEther("1"));

      await asset.connect(investor).approve(poolLogicProxy.address, parseEther("1"));
      await poolLogicProxy.connect(investor).deposit(asset.address, parseEther("1"));

      expect(await asset.balanceOf(poolLogicProxy.address)).to.equal(parseEther("1"));
    });
  });
});
