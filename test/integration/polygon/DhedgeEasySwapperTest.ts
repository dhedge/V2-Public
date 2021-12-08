import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect, use } from "chai";
import { solidity } from "ethereum-waffle";
import { BigNumber } from "ethers";
import { ethers } from "hardhat";
import { DhedgeEasySwapper, PoolFactory, PoolLogic, PoolManagerLogic } from "../../../types";
import { units } from "../../TestHelpers";
import { aave, assets, assetsBalanceOfSlot, quickswap } from "../polygon-data";
import { getAccountToken } from "../utils/getAccountTokens";

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
  let logicOwner: SignerWithAddress;
  let dhedgeEasySwapper: DhedgeEasySwapper;
  let poolFactory: PoolFactory;

  const ETHBEAR2X = "0xf4b3a195587d2735b656b7ffe9060f478faf1b32";
  const ETHBULL3X = "0x3e5f7e9e7dc3bc3086ccebd5eb59a0a4a29d881b";
  const BTCBEAR2X = "0xcc940b5c6136994bed41bff5d88b170929921e9e";
  const BTCBULL3X = "0xc8fa09426ce1aeac1bc28751f1f6c8d74fa53f3c";

  before(async function () {
    [logicOwner] = await ethers.getSigners();

    const poolFactoryProxy = "0xfdc7b8bFe0DD3513Cc669bB8d601Cb83e2F69cB0";
    const proxyAdminAddress = "0x0C0a10C9785a73018077dBC74B2A006695849252";

    poolFactory = await ethers.getContractAt("PoolFactory", poolFactoryProxy);

    // Take over ownership of the poolFactoryProxy
    // const owner = await ethers.provider.getStorageAt(poolFactoryProxy, 101);
    await ethers.provider.send("hardhat_setStorageAt", [
      poolFactoryProxy,
      BigNumber.from(101).toHexString(),
      "0x000000000000000000000000f39fd6e51aad88f6f4ce6ab8827279cfffb92266",
    ]);
    await ethers.provider.send("evm_mine", []); // Just mines to the next block

    ///
    /// ONCE Prod is updated below can be removed
    ///

    // Take over ownership of the proxyAdmin
    const proxyAdmin = await ethers.getContractAt("ProxyAdmin", proxyAdminAddress);
    await ethers.provider.send("hardhat_setStorageAt", [
      proxyAdminAddress,
      "0x0",
      "0x000000000000000000000000f39fd6e51aad88f6f4ce6ab8827279cfffb92266",
    ]);
    await ethers.provider.send("evm_mine", []); // Just mines to the next block
    expect(await poolFactory.owner()).to.equal(logicOwner.address);

    const PoolFactoryContract = await ethers.getContractFactory("PoolFactory");
    const newPoolFactory = await PoolFactoryContract.deploy();
    await newPoolFactory.deployed();

    await proxyAdmin.upgrade(poolFactoryProxy, newPoolFactory.address);

    const PoolPerformance = await ethers.getContractFactory("PoolPerformance");
    const poolPerformance = await PoolPerformance.deploy();
    await poolPerformance.deployed();

    await poolFactory.setPoolPerformanceAddress(poolPerformance.address);

    const PoolLogic = await ethers.getContractFactory("PoolLogic");
    const poolLogic = await PoolLogic.deploy();
    await poolLogic.deployed();
    const PoolManagerLogic = await ethers.getContractFactory("PoolManagerLogic");
    const poolManagerLogic = await PoolManagerLogic.deploy();
    await poolManagerLogic.deployed();

    await poolFactory.setLogic(poolLogic.address, await poolManagerLogic.address);

    ///
    /// ONCE Prod is updated above can be removed ^^^
    ///

    const DhedgeEasySwapper = await ethers.getContractFactory("DhedgeEasySwapper");
    dhedgeEasySwapper = await DhedgeEasySwapper.deploy(quickswap.router, assets.weth);
    await dhedgeEasySwapper.deployed();

    // AavelendingPool
    await dhedgeEasySwapper.setAssetToSkip(aave.lendingPool, true);

    await poolFactory.addTransferWhitelist(dhedgeEasySwapper.address);
    expect(await poolFactory.isTransferWhitelisted(dhedgeEasySwapper.address, dhedgeEasySwapper.address)).to.be.true;
  });

  describe("allowedPools", () => {
    it("only approved pools can use Swapper", async () => {
      expect(dhedgeEasySwapper.deposit(ETHBEAR2X, assets.usdc, units(1, 6), assets.usdc, 0)).to.be.revertedWith(
        "Pool is not allowed.",
      );
    });
  });

  describe("Toros Tests", () => {
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
          await dhedgeEasySwapper.withdraw(ETHBEAR2X, balanceBefore, withdrawToken, 0);
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

        // Withdraw all
        await torosPool.approve(dhedgeEasySwapper.address, balance);

        // Here I need update this to calculate the withdrawal amount out in withdraw token
        await dhedgeEasySwapper.withdraw(torosPool.address, balance, withdrawToken, 0);

        // All tokens were withdrawn
        const balanceAfterWithdraw = await torosPool.balanceOf(logicOwner.address);
        expect(balanceAfterWithdraw).to.equal(0);

        // Check we received back funds close to the value of what we deposited
        const WithdrawToken = await ethers.getContractAt("IERC20", withdrawToken);
        const fundsReturned = await WithdrawToken.balanceOf(logicOwner.address);

        const withdrawAmountUSDC = await poolManagerLogicProxy["assetValue(address,uint256)"](
          withdrawToken,
          fundsReturned,
        );

        // Funds returned should be close to funds in
        const difference = depositAssetValueInUSDC.div(depositAssetValueInUSDC.sub(withdrawAmountUSDC));
        console.log("Total in out Slippage %", 100 / difference.toNumber());
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
        torosPoolAddress: ETHBEAR2X,
        userDepositToken: assets.usdc,
        depositAmount: units(1, 6),
        userDepositTokenSlot: assetsBalanceOfSlot.usdc,
        poolDepositToken: assets.usdc,
        withdrawToken: assets.usdc,
      },
      {
        testName: "ETHBEAR2X - can deposit and withdraw - swap in, swap out",
        torosPoolAddress: ETHBEAR2X,
        userDepositToken: assets.weth,
        depositAmount: units(1),
        userDepositTokenSlot: assetsBalanceOfSlot.weth,
        poolDepositToken: assets.usdc,
        withdrawToken: assets.weth,
      },
      {
        testName: "ETHBULL3X - can deposit and withdraw - no swap on the way in, swap out",
        torosPoolAddress: ETHBULL3X,
        userDepositToken: assets.weth,
        depositAmount: units(1),
        userDepositTokenSlot: assetsBalanceOfSlot.weth,
        poolDepositToken: assets.weth,
        withdrawToken: assets.weth,
      },
      {
        testName: "ETHBULL3X - can deposit and withdraw - swap in, swap out",
        torosPoolAddress: ETHBULL3X,
        userDepositToken: assets.usdc,
        depositAmount: units(1, 6),
        userDepositTokenSlot: assetsBalanceOfSlot.usdc,
        poolDepositToken: assets.weth,
        withdrawToken: assets.usdc,
      },

      {
        testName: "BTCBEAR2X - can deposit and withdraw - no swap on the way in, swap on way out",
        torosPoolAddress: BTCBEAR2X,
        userDepositToken: assets.usdc,
        depositAmount: units(1, 6),
        userDepositTokenSlot: assetsBalanceOfSlot.usdc,
        poolDepositToken: assets.usdc,
        withdrawToken: assets.usdc,
      },

      {
        testName: "BTCBEAR2X - can deposit and withdraw - swap in, swap out",
        torosPoolAddress: BTCBEAR2X,
        userDepositToken: assets.weth,
        depositAmount: units(1),
        userDepositTokenSlot: assetsBalanceOfSlot.weth,
        poolDepositToken: assets.usdc,
        withdrawToken: assets.weth,
      },
      {
        testName: "BTCBULL3X - can deposit and withdraw - no swap on the way in, swap out",
        torosPoolAddress: BTCBULL3X,
        userDepositToken: assets.wbtc,
        depositAmount: units(1, 7), // 0.1 btc (I think)
        userDepositTokenSlot: assetsBalanceOfSlot.wbtc,
        poolDepositToken: assets.wbtc,
        withdrawToken: assets.wbtc,
      },
      {
        testName: "BTCBULL3X - can deposit and withdraw - swap in, swap out",
        torosPoolAddress: BTCBULL3X,
        userDepositToken: assets.usdc,
        depositAmount: units(1, 6),
        userDepositTokenSlot: assetsBalanceOfSlot.usdc,
        poolDepositToken: assets.wbtc,
        withdrawToken: assets.usdc,
      },
    ];

    tests.forEach(createTest);
  });
});
