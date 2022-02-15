import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect, use } from "chai";
import { solidity } from "ethereum-waffle";
import { BigNumber } from "ethers";
import { ethers } from "hardhat";
import {
  aave,
  assets,
  assetsBalanceOfSlot,
  quickswap,
  sushi,
  torosPools,
} from "../../../config/chainData/polygon-data";
import { DhedgeEasySwapper, Governance, PoolFactory, PoolManagerLogic } from "../../../types";
import { units } from "../../TestHelpers";
import { getAccountToken } from "../utils/getAccountTokens";

const { toBytes32 } = require("../../TestHelpers");

use(solidity);

interface TestCase {
  testName: string;
  torosPoolAddress: string;
  userDepositToken: string;
  userDepositTokenSlot: number;
  poolDepositToken: string;
  depositAmount: BigNumber;
  withdrawToken: string;
}

describe("DhedgeEasySwapper", function () {
  let logicOwner: SignerWithAddress, user1: SignerWithAddress, user2: SignerWithAddress, feeSink: SignerWithAddress;
  let dhedgeEasySwapper: DhedgeEasySwapper;
  let poolFactory: PoolFactory;
  let governance: Governance;

  before(async function () {
    [logicOwner, user1, user2, feeSink] = await ethers.getSigners();

    const poolFactoryProxy = "0xfdc7b8bFe0DD3513Cc669bB8d601Cb83e2F69cB0";

    poolFactory = await ethers.getContractAt("PoolFactory", poolFactoryProxy);

    // Take over ownership of the poolFactoryProxy
    // const owner = await ethers.provider.getStorageAt(poolFactoryProxy, 101);
    await ethers.provider.send("hardhat_setStorageAt", [
      poolFactoryProxy,
      BigNumber.from(101).toHexString(),
      "0x000000000000000000000000f39fd6e51aad88f6f4ce6ab8827279cfffb92266",
    ]);
    await ethers.provider.send("evm_mine", []); // Just mines to the next block

    const SwapRouter = await ethers.getContractFactory("DhedgeSwapRouter");
    const swapRouter = await SwapRouter.deploy([quickswap.router, sushi.router], []); // removed curve pools
    await swapRouter.deployed();

    const governanceAddress = "0x206CbDa3381e7afdF448621b90f549f89555A588";
    governance = await ethers.getContractAt("Governance", governanceAddress);
    // // Take over ownership of the governance
    // const governanceOwner = await ethers.provider.getStorageAt(governance.address, 0);
    await ethers.provider.send("hardhat_setStorageAt", [
      governance.address,
      "0x0",
      "0x000000000000000000000000f39fd6e51aad88f6f4ce6ab8827279cfffb92266",
    ]);
    await ethers.provider.send("evm_mine", []); // Just mines to the next block

    await governance.setAddresses([{ name: toBytes32("swapRouter"), destination: swapRouter.address }]);

    const DhedgeEasySwapper = await ethers.getContractFactory("DhedgeEasySwapper");
    dhedgeEasySwapper = await DhedgeEasySwapper.deploy(feeSink.address, swapRouter.address, assets.weth);
    // dhedgeEasySwapper = await DhedgeEasySwapper.deploy(feeSink.address, quickswap.router, assets.weth);
    await dhedgeEasySwapper.deployed();

    // AavelendingPool
    await dhedgeEasySwapper.setAssetToSkip(aave.lendingPool, true);
    await dhedgeEasySwapper.setFee(0, 0);

    await poolFactory.addTransferWhitelist(dhedgeEasySwapper.address);
    expect(await poolFactory.transferWhitelist(dhedgeEasySwapper.address)).to.be.true;
  });

  describe("allowedPools", () => {
    it("only approved pools can use Swapper", async () => {
      expect(
        dhedgeEasySwapper.deposit(torosPools.ETHBEAR2X, assets.usdc, units(1, 6), assets.usdc, 0),
      ).to.be.revertedWith("Pool is not allowed.");
    });
  });

  describe("takes fee", () => {
    it("fee sink receives fee", async () => {
      const depositAmount = units(1, 6);
      await getAccountToken(depositAmount, logicOwner.address, assets.usdc, assetsBalanceOfSlot.usdc);

      // Whitelist
      const torosPool = await ethers.getContractAt("PoolLogic", torosPools.ETHBEAR2X);
      await dhedgeEasySwapper.setPoolAllowed(torosPool.address, true);
      await dhedgeEasySwapper.setFee(1, 100); // 1%

      const DepositToken = await ethers.getContractAt("IERC20", assets.usdc);
      await DepositToken.approve(dhedgeEasySwapper.address, depositAmount);
      // Check feeSink is empty
      const balanceBEfore = await DepositToken.balanceOf(feeSink.address);
      // Deposit
      await dhedgeEasySwapper.deposit(torosPools.ETHBEAR2X, assets.usdc, depositAmount, assets.usdc, 0);
      // Fee of 1% received by fee sink
      const balanceAfter = await DepositToken.balanceOf(feeSink.address);
      expect(balanceAfter.sub(balanceBEfore)).to.equal(depositAmount.div(100));
      await dhedgeEasySwapper.setFee(0, 0); // 1%
    });
  });

  describe("FlashSwap Test", () => {
    it("cannot deposit and withdraw in one block", async () => {
      // Setup
      const FlashSwapperTest = await ethers.getContractFactory("FlashSwapperTest");
      const flashSwapperTest = await FlashSwapperTest.deploy();
      await flashSwapperTest.deployed();
      const depositAmount = units(1, 6);
      await getAccountToken(depositAmount, logicOwner.address, assets.usdc, assetsBalanceOfSlot.usdc);
      // Whitelist
      const torosPool = await ethers.getContractAt("PoolLogic", torosPools.ETHBEAR2X);
      await dhedgeEasySwapper.setPoolAllowed(torosPool.address, true);

      const DepositToken = await ethers.getContractAt("IERC20", assets.usdc);
      await DepositToken.approve(flashSwapperTest.address, depositAmount);
      // Test
      await expect(
        flashSwapperTest.flashSwap(dhedgeEasySwapper.address, torosPool.address, assets.usdc, depositAmount),
      ).to.be.revertedWith("whitelist cooldown active");
    });

    it("cannot use swapper then withdraw directly from pool", async () => {
      // Ensures against the Circumvention of the 1 block, flash attack protection
      // Setup
      const FlashSwapperTest = await ethers.getContractFactory("FlashSwapperTest");
      const flashSwapperTest = await FlashSwapperTest.deploy();
      await flashSwapperTest.deployed();
      const depositAmount = units(1, 6);
      await getAccountToken(depositAmount, logicOwner.address, assets.usdc, assetsBalanceOfSlot.usdc);
      // Whitelist
      const torosPool = await ethers.getContractAt("PoolLogic", torosPools.ETHBEAR2X);
      await dhedgeEasySwapper.setPoolAllowed(torosPool.address, true);

      const DepositToken = await ethers.getContractAt("IERC20", assets.usdc);
      await DepositToken.approve(flashSwapperTest.address, depositAmount);
      // Test
      await expect(
        flashSwapperTest.flashSwapDirectWithdraw(
          dhedgeEasySwapper.address,
          torosPool.address,
          assets.usdc,
          depositAmount,
        ),
      ).to.be.revertedWith("whitelist cooldown active");
    });
  });

  describe("Not using the swapper", () => {
    it("24 hour lock up still works", async () => {
      /// NOTE we operate as user1.address in this test so that we don't trigger wallet cooldown for other tests
      // Setup
      const depositAmount = units(1, 6);
      await getAccountToken(depositAmount, user1.address, assets.usdc, assetsBalanceOfSlot.usdc);
      const torosPool = await ethers.getContractAt("PoolLogic", torosPools.ETHBEAR2X);
      const DepositToken = await ethers.getContractAt("IERC20", assets.usdc);
      await DepositToken.connect(user1).approve(torosPool.address, depositAmount);

      // Deposit
      torosPool.connect(user1).deposit(assets.usdc, depositAmount);
      const balance = await torosPool.connect(user1).balanceOf(user1.address);
      // Withdraw
      await ethers.provider.send("evm_increaseTime", [3600]); // 1 hour
      await expect(torosPool.connect(user1).withdraw(balance)).to.be.revertedWith("cooldown active");
    });
  });

  describe("Multiple users can use swapper at the same time", () => {
    it("2 users deposit, wait, withdraw", async () => {
      const userDepositToken = assets.usdc;
      const userDepositTokenSlot = assetsBalanceOfSlot.usdc;
      const poolDepositToken = assets.usdc;
      const withdrawToken = assets.usdc;
      const torosPool = await ethers.getContractAt("PoolLogic", torosPools.ETHBEAR2X);
      await dhedgeEasySwapper.setPoolAllowed(torosPool.address, true);

      const DepositToken = await ethers.getContractAt("IERC20", assets.usdc);
      const depositAmount = units(1, 6);

      await getAccountToken(depositAmount, logicOwner.address, userDepositToken, userDepositTokenSlot);
      await getAccountToken(depositAmount, user2.address, userDepositToken, userDepositTokenSlot);

      expect(await DepositToken.balanceOf(logicOwner.address)).to.equal(depositAmount);
      expect(await DepositToken.balanceOf(user2.address)).to.equal(depositAmount);

      await DepositToken.approve(dhedgeEasySwapper.address, depositAmount);
      await DepositToken.connect(user2).approve(dhedgeEasySwapper.address, depositAmount);

      await dhedgeEasySwapper.deposit(torosPool.address, userDepositToken, depositAmount, poolDepositToken, 0);
      await dhedgeEasySwapper
        .connect(user2)
        .deposit(torosPool.address, userDepositToken, depositAmount, poolDepositToken, 0);

      const balanceLogicOwner = await torosPool.balanceOf(logicOwner.address);
      const balanceUser2 = await torosPool.balanceOf(user2.address);

      await ethers.provider.send("evm_increaseTime", [60 * 6]); // 6 minutes

      // Withdraw all
      await torosPool.approve(dhedgeEasySwapper.address, balanceLogicOwner);
      await torosPool.connect(user2).approve(dhedgeEasySwapper.address, balanceUser2);

      await dhedgeEasySwapper.withdraw(torosPool.address, balanceLogicOwner, withdrawToken, 0);
      await dhedgeEasySwapper.connect(user2).withdraw(torosPool.address, balanceUser2, withdrawToken, 0);
    });

    it("one user deposits, waits, second user deposits, first user immediate withdraw", async () => {
      const userDepositToken = assets.usdc;
      const userDepositTokenSlot = assetsBalanceOfSlot.usdc;
      const poolDepositToken = assets.usdc;
      const withdrawToken = assets.usdc;
      const torosPool = await ethers.getContractAt("PoolLogic", torosPools.ETHBEAR2X);
      await dhedgeEasySwapper.setPoolAllowed(torosPool.address, true);

      const DepositToken = await ethers.getContractAt("IERC20", assets.usdc);
      const depositAmount = units(1, 6);

      await getAccountToken(depositAmount, logicOwner.address, userDepositToken, userDepositTokenSlot);
      await getAccountToken(depositAmount, user2.address, userDepositToken, userDepositTokenSlot);

      expect(await DepositToken.balanceOf(logicOwner.address)).to.equal(depositAmount);
      expect(await DepositToken.balanceOf(user2.address)).to.equal(depositAmount);

      await DepositToken.approve(dhedgeEasySwapper.address, depositAmount);
      await DepositToken.connect(user2).approve(dhedgeEasySwapper.address, depositAmount);

      await dhedgeEasySwapper.deposit(torosPool.address, userDepositToken, depositAmount, poolDepositToken, 0);
      const balanceLogicOwner = await torosPool.balanceOf(logicOwner.address);

      await ethers.provider.send("evm_increaseTime", [60 * 6]); // 6 minutes

      // Withdraw all
      await dhedgeEasySwapper
        .connect(user2)
        .deposit(torosPool.address, userDepositToken, depositAmount, poolDepositToken, 0);
      const balanceUser2 = await torosPool.balanceOf(user2.address);

      await torosPool.approve(dhedgeEasySwapper.address, balanceLogicOwner);
      await dhedgeEasySwapper.withdraw(torosPool.address, balanceLogicOwner, withdrawToken, 0);

      await ethers.provider.send("evm_increaseTime", [60 * 6]); // 6 minutes
      await torosPool.connect(user2).approve(dhedgeEasySwapper.address, balanceUser2);
      await dhedgeEasySwapper.connect(user2).withdraw(torosPool.address, balanceUser2, withdrawToken, 0);
    });
  });

  describe("Toros Tests", () => {
    let snapshot: any;
    beforeEach(async function () {
      snapshot = await ethers.provider.send("evm_snapshot", []);
      [logicOwner, user1, user2, feeSink] = await ethers.getSigners();
    });
    afterEach(async () => {
      await ethers.provider.send("evm_revert", [snapshot]);
    });

    const createTest = (test: TestCase) => {
      const {
        testName,
        torosPoolAddress,
        userDepositToken,
        userDepositTokenSlot,
        depositAmount,
        withdrawToken,
        poolDepositToken,
      } = test;
      it(testName, async () => {
        const torosPool = await ethers.getContractAt("PoolLogic", torosPoolAddress);
        await dhedgeEasySwapper.setPoolAllowed(torosPool.address, true);

        // Reset token ownership - for when other tests fail
        const balanceBefore = await torosPool.balanceOf(logicOwner.address);
        if (balanceBefore > BigNumber.from(0)) {
          await torosPool.approve(dhedgeEasySwapper.address, balanceBefore);
          await dhedgeEasySwapper.withdraw(torosPool.address, balanceBefore, withdrawToken, 0);
        }

        // TokenPrice is in 10**18
        // But usdc is in 10**6
        // And asset price in 10**18 hurt my brain
        const tokenPriceInUSDC = await torosPool.tokenPrice();
        const PoolManagerLogic = await ethers.getContractFactory("PoolManagerLogic");
        const poolManagerLogicProxy: PoolManagerLogic = await PoolManagerLogic.attach(
          await torosPool.poolManagerLogic(),
        );

        const depositAssetValueInUSDC = await poolManagerLogicProxy["assetValue(address,uint256)"](
          userDepositToken,
          depositAmount,
        );

        console.log("depositAssetValueInUSDC $", depositAssetValueInUSDC.div(units(1)).toString());
        console.log("totalFundValue $", (await poolManagerLogicProxy.totalFundValue()).div(units(1)).toString());

        const expectedTokens = depositAssetValueInUSDC.mul(units(1)).div(tokenPriceInUSDC.toString());

        const DepositToken = await ethers.getContractAt("IERC20", userDepositToken);
        await getAccountToken(depositAmount, logicOwner.address, userDepositToken, userDepositTokenSlot);
        expect(await DepositToken.balanceOf(logicOwner.address)).to.equal(depositAmount);

        await DepositToken.approve(dhedgeEasySwapper.address, depositAmount);
        // deposit the cost of 1 token
        await dhedgeEasySwapper.deposit(
          torosPool.address,
          userDepositToken,
          depositAmount,
          poolDepositToken,
          // 5% slippage
          expectedTokens.div(100).mul(95),
        );

        // Make sure we received very close to one token
        const balance = await torosPool.balanceOf(logicOwner.address);
        expect(balance).to.be.closeTo(expectedTokens, expectedTokens.div(100) as unknown as number);
        expect(await DepositToken.balanceOf(logicOwner.address)).to.equal(0);

        await ethers.provider.send("evm_increaseTime", [60 * 6]); // 6 minutes

        // Withdraw all
        await torosPool.approve(dhedgeEasySwapper.address, balance);
        const WithdrawToken = await ethers.getContractAt("IERC20", withdrawToken);
        const beforeFundsReturnedBalance = await WithdrawToken.balanceOf(logicOwner.address);
        // Here I need update this to calculate the withdrawal amount out in withdraw token
        await dhedgeEasySwapper.withdraw(torosPool.address, balance, withdrawToken, 0);

        // All tokens were withdrawn
        const balanceAfterWithdraw = await torosPool.balanceOf(logicOwner.address);
        expect(balanceAfterWithdraw).to.equal(0);

        // Check we received back funds close to the value of what we deposited
        const afterFundsReturnedBalance = await WithdrawToken.balanceOf(logicOwner.address);
        const fundsReturned = afterFundsReturnedBalance.sub(beforeFundsReturnedBalance);

        const withdrawAmountUSDC = await poolManagerLogicProxy["assetValue(address,uint256)"](
          withdrawToken,
          fundsReturned,
        );

        // Funds returned should be close to funds in
        const difference = depositAssetValueInUSDC.div(depositAssetValueInUSDC.sub(withdrawAmountUSDC));
        console.log("Total in out Slippage %", 100 / difference.toNumber());

        if (userDepositToken === withdrawToken) {
          if (fundsReturned > depositAmount) {
            console.log("Returned amount is more than deposit amount");
          }
        }
        // Funds returned should be close to funds in
        expect(withdrawAmountUSDC).closeTo(
          depositAssetValueInUSDC,
          // 2% - in and out slippage is quite a bit 605570-595902
          depositAssetValueInUSDC.div(100).mul(3) as unknown as number,
        );
      });
    };

    const tests: TestCase[] = [
      {
        testName: "ETHBEAR2X - can deposit and withdraw - no swap on in or out",
        torosPoolAddress: torosPools.ETHBEAR2X,
        userDepositToken: assets.usdc,
        depositAmount: units(20000, 6),
        userDepositTokenSlot: assetsBalanceOfSlot.usdc,
        poolDepositToken: assets.usdc,
        withdrawToken: assets.usdc,
      },
      {
        testName: "ETHBEAR2X - can deposit and withdraw - swap in, swap out",
        torosPoolAddress: torosPools.ETHBEAR2X,
        userDepositToken: assets.weth,
        depositAmount: units(1),
        userDepositTokenSlot: assetsBalanceOfSlot.weth,
        poolDepositToken: assets.usdc,
        withdrawToken: assets.weth,
      },

      {
        testName: "ETHBULL3X - can deposit and withdraw - no swap on the way in, swap out",
        torosPoolAddress: torosPools.ETHBULL3X,
        userDepositToken: assets.weth,
        depositAmount: units(3),
        userDepositTokenSlot: assetsBalanceOfSlot.weth,
        poolDepositToken: assets.weth,
        withdrawToken: assets.weth,
      },

      {
        testName: "ETHBULL3X - can deposit and withdraw - swap in, swap out",
        torosPoolAddress: torosPools.ETHBULL3X,
        userDepositToken: assets.usdc,
        depositAmount: units(1, 6),
        userDepositTokenSlot: assetsBalanceOfSlot.usdc,
        poolDepositToken: assets.weth,
        withdrawToken: assets.usdc,
      },

      {
        testName: "BTCBEAR2X - can deposit and withdraw - no swap on the way in, swap on way out",
        torosPoolAddress: torosPools.BTCBEAR2X,
        userDepositToken: assets.usdc,
        depositAmount: units(20000, 6),
        userDepositTokenSlot: assetsBalanceOfSlot.usdc,
        poolDepositToken: assets.usdc,
        withdrawToken: assets.usdc,
      },

      {
        testName: "BTCBEAR2X - can deposit and withdraw - swap in, swap out",
        torosPoolAddress: torosPools.BTCBEAR2X,
        userDepositToken: assets.weth,
        depositAmount: units(1),
        userDepositTokenSlot: assetsBalanceOfSlot.weth,
        poolDepositToken: assets.usdc,
        withdrawToken: assets.weth,
      },

      {
        testName: "BTCBULL3X - can deposit and withdraw - no swap on the way in, swap out",
        torosPoolAddress: torosPools.BTCBULL3X,
        userDepositToken: assets.wbtc,
        depositAmount: units(1, 7), // 0.1 btc (I think)
        userDepositTokenSlot: assetsBalanceOfSlot.wbtc,
        poolDepositToken: assets.wbtc,
        withdrawToken: assets.wbtc,
      },

      {
        testName: "BTCBULL3X - can deposit and withdraw - swap in, swap out",
        torosPoolAddress: torosPools.BTCBULL3X,
        userDepositToken: assets.usdc,
        depositAmount: units(10000, 6),
        userDepositTokenSlot: assetsBalanceOfSlot.usdc,
        poolDepositToken: assets.wbtc,
        withdrawToken: assets.usdc,
      },
    ];

    tests.forEach(createTest);
  });
});
