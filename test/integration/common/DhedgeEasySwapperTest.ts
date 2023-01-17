import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { BigNumber } from "ethers";
import { ethers, upgrades } from "hardhat";
import {
  DhedgeEasySwapper,
  Governance,
  PoolFactory,
  PoolManagerLogic,
  IERC20__factory,
  DhedgeEasySwapper__factory,
  EasySwapperGuard,
} from "../../../types";
import { checkAlmostSame, units } from "../../TestHelpers";
import { getAccountToken } from "../utils/getAccountTokens";

import { toBytes32 } from "../../TestHelpers";
import { utils } from "../utils/utils";
import { createFund } from "../utils/createFund";
import { ChainDataCommon } from "../../../config/chainData/ChainDataType";
import { Address } from "../../../deployment-scripts/types";

export interface EasySwapperCommonTestCase {
  testName: string;
  dhedgePoolAddress: string;
  poolDepositToken: string;
}

export interface EasySwapperTestCase extends EasySwapperCommonTestCase {
  userDepositToken: string;
  userDepositTokenSlot: number;
  withdrawToken: string;
  depositAmount: BigNumber;
}

export interface EasySwapperNativeTestCase extends EasySwapperCommonTestCase {
  nativeAssetDepositAmount: BigNumber;
}

export const DhedgeEasySwapperTests = (
  poolFactoryProxy: string,
  baseTestDhedgePoolMustAcceptUSDC: Address,
  withdrawNormalTestCases: EasySwapperTestCase[],
  withdrawSUSDTestCases: EasySwapperTestCase[],
  withdrawNativeTestCases: EasySwapperNativeTestCase[],
  chainData: ChainDataCommon,
  nativeAssetWrapper: Address,
  emptyNeverFundedDhedgePoolMustAcceptWETH: Address,
) => {
  const { assets, assetsBalanceOfSlot, v2Routers, uniswapV3, velodrome } = chainData;
  // Must accept usdc
  const BASE_TEST_POOL = baseTestDhedgePoolMustAcceptUSDC;
  describe("DhedgeEasySwapper Toros Tests", function () {
    let logicOwner: SignerWithAddress, user1: SignerWithAddress, user2: SignerWithAddress, feeSink: SignerWithAddress;
    let dhedgeEasySwapper: DhedgeEasySwapper;
    let poolFactory: PoolFactory;
    let governance: Governance;
    let snapId: string;
    let easySwapperGuard: EasySwapperGuard;

    beforeEach(async () => {
      snapId = await utils.evmTakeSnap();
    });

    afterEach(async () => {
      await utils.evmRestoreSnap(snapId);
    });

    before(async function () {
      [logicOwner, user1, user2, feeSink] = await ethers.getSigners();

      poolFactory = await ethers.getContractAt("PoolFactory", poolFactoryProxy);
      const PoolFactory = await ethers.getContractFactory("PoolFactory");

      const proxyAdmin = await ethers.getContractAt("ProxyAdmin", chainData.proxyAdmin);
      const poolFactoryOwner = await utils.impersonateAccount(await poolFactory.owner());
      proxyAdmin.connect(poolFactoryOwner).upgrade(poolFactoryProxy, (await PoolFactory.deploy()).address);

      const PoolLogic = await ethers.getContractFactory("PoolLogic");
      const PoolManagerLogic = await ethers.getContractFactory("PoolManagerLogic");
      poolFactory
        .connect(poolFactoryOwner)
        .setLogic((await PoolLogic.deploy()).address, (await PoolManagerLogic.deploy()).address);

      const UniV3V2SwapRouter = await ethers.getContractFactory("DhedgeUniV3V2Router");
      const v3v2SwapRouter = await UniV3V2SwapRouter.deploy(uniswapV3.factory, uniswapV3.router);
      await v3v2SwapRouter.deployed();

      if (velodrome) {
        const DhedgeVeloV2Router = await ethers.getContractFactory("DhedgeVeloV2Router");
        const dhedgeVeloV2Router = await DhedgeVeloV2Router.deploy(velodrome.router);
        await dhedgeVeloV2Router.deployed();
        v2Routers.push(dhedgeVeloV2Router.address);
      }

      const DHedgePoolAggregator = await ethers.getContractFactory("DHedgePoolAggregator");
      const dHedgePoolAggregator = await DHedgePoolAggregator.deploy(BASE_TEST_POOL);
      await dHedgePoolAggregator.deployed();

      const SwapRouter = await ethers.getContractFactory("DhedgeSuperSwapper");
      const swapRouter = await SwapRouter.deploy([v3v2SwapRouter.address, ...v2Routers], []);
      await swapRouter.deployed();

      const EasySwapperGuard = await ethers.getContractFactory("EasySwapperGuard");
      easySwapperGuard = await EasySwapperGuard.deploy();
      await easySwapperGuard.deployed();

      const DhedgeEasySwapper = await ethers.getContractFactory("DhedgeEasySwapper");
      dhedgeEasySwapper = <DhedgeEasySwapper>await upgrades.deployProxy(DhedgeEasySwapper, [
        feeSink.address,
        0, // fee numerator
        0, // fee denominator
      ]);
      await dhedgeEasySwapper.deployed();
      await dhedgeEasySwapper.setWithdrawProps({
        swapRouter: swapRouter.address,
        weth: assets.weth,
        // Not used - Kept for upgradability
        assetType2Router: chainData.ZERO_ADDRESS,
        // Not used - Kept for upgradability
        assetType5Router: chainData.ZERO_ADDRESS,
        synthetixProps: {
          swapSUSDToAsset: assets.usdc,
          sUSDProxy: assets.susd || chainData.ZERO_ADDRESS,
          snxProxy: assets.snxProxy || chainData.ZERO_ADDRESS,
        },
        nativeAssetWrapper,
      });

      const assetHandler = await ethers.getContractAt("AssetHandler", await poolFactory.getAssetHandler());

      const assetHandlerOwner = await utils.impersonateAccount(await assetHandler.owner());
      // Manual overwriting the synthetix assets to type 1
      // Can remove these once the assets are configured correctly
      assetHandler.connect(assetHandlerOwner).addAssets([
        {
          asset: BASE_TEST_POOL, // enables Toros pool as an asset
          assetType: "0",
          aggregator: dHedgePoolAggregator.address,
        },
      ]);

      governance = await ethers.getContractAt(
        "Governance",
        await poolFactory.connect(poolFactoryOwner).governanceAddress(),
      );

      const govSigner = await utils.impersonateAccount(await governance.owner());
      await governance.connect(govSigner).setAssetGuard(1, await governance.assetGuards(0));
      await governance.connect(govSigner).setContractGuard(dhedgeEasySwapper.address, easySwapperGuard.address);
      await governance
        .connect(govSigner)
        .setAddresses([{ name: toBytes32("swapRouter"), destination: swapRouter.address }]);
      await governance.connect(govSigner).setAddresses([{ name: toBytes32("weth"), destination: assets.weth }]);

      await dhedgeEasySwapper.setFee(0, 0);

      await poolFactory.connect(poolFactoryOwner).addCustomCooldownWhitelist(dhedgeEasySwapper.address);
      expect(await poolFactory.connect(poolFactoryOwner).customCooldownWhitelist(dhedgeEasySwapper.address)).to.be.true;
    });

    describe("fees", () => {
      it("fee sink receives fee", async () => {
        const depositAmount = units(1, 6);
        await getAccountToken(depositAmount, logicOwner.address, assets.usdc, assetsBalanceOfSlot.usdc);

        // Whitelist
        const torosPool = await ethers.getContractAt("PoolLogic", BASE_TEST_POOL);
        await dhedgeEasySwapper.setPoolAllowed(torosPool.address, true);
        await dhedgeEasySwapper.setFee(1, 100); // 1%

        const DepositToken = await ethers.getContractAt(
          "@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20",
          assets.usdc,
        );
        await DepositToken.approve(dhedgeEasySwapper.address, depositAmount);
        // Check feeSink is empty
        const balanceBefore = await DepositToken.balanceOf(feeSink.address);
        // Deposit
        await dhedgeEasySwapper.deposit(BASE_TEST_POOL, assets.usdc, depositAmount, assets.usdc, 0);
        // Fee of 1% received by fee sink
        const balanceAfter = await DepositToken.balanceOf(feeSink.address);
        expect(balanceAfter.sub(balanceBefore)).to.equal(depositAmount.div(100));
        await dhedgeEasySwapper.setFee(0, 0);
      });

      it("pool manager fee bypass works", async () => {
        // Invest into Toros pool from a manager pool
        // The manager is whitelisted to bypass fee
        const DepositToken = await ethers.getContractAt(
          "@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20",
          assets.usdc,
        );
        const depositAmount = units(1, 6);
        await getAccountToken(depositAmount, user1.address, assets.usdc, assetsBalanceOfSlot.usdc);

        const funds = await createFund(poolFactory, logicOwner, user1, [
          { asset: DepositToken.address, isDeposit: true },
          { asset: BASE_TEST_POOL, isDeposit: false },
        ]);
        const feeBypassPool = funds.poolLogicProxy;
        // Deposit into manager pool
        await DepositToken.connect(user1).approve(feeBypassPool.address, depositAmount);
        await feeBypassPool.connect(user1).deposit(DepositToken.address, depositAmount);
        // Whitelist Toros pool in EasySwapper
        const torosPool = await ethers.getContractAt("PoolLogic", BASE_TEST_POOL);
        await dhedgeEasySwapper.setPoolAllowed(torosPool.address, true);
        await dhedgeEasySwapper.setFee(1, 100); // 1%

        // Set pool manager fee bypass
        await dhedgeEasySwapper.setManagerFeeBypass(user1.address, true);

        // Check feeSink is empty
        const balanceBefore = await DepositToken.balanceOf(feeSink.address);

        // Buy Toros pool from manager pool
        const iERC20 = new ethers.utils.Interface(IERC20__factory.abi);
        const dhedgeEasySwapperAbi = new ethers.utils.Interface(DhedgeEasySwapper__factory.abi);
        const approveData = iERC20.encodeFunctionData("approve", [dhedgeEasySwapper.address, depositAmount]);
        await feeBypassPool.connect(user1).execTransaction(DepositToken.address, approveData);
        const easySwapperDepositData = dhedgeEasySwapperAbi.encodeFunctionData("deposit", [
          torosPool.address,
          DepositToken.address,
          depositAmount,
          DepositToken.address,
          0,
        ]);

        // Deposit from manager pool
        await feeBypassPool.connect(user1).execTransaction(dhedgeEasySwapper.address, easySwapperDepositData);
        // No fee should be received by the fee sink
        const balanceAfter = await DepositToken.balanceOf(feeSink.address);
        expect(balanceAfter.sub(balanceBefore)).to.equal(0);
        await dhedgeEasySwapper.setFee(0, 0);
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
        const torosPool = await ethers.getContractAt("PoolLogic", BASE_TEST_POOL);
        await dhedgeEasySwapper.setPoolAllowed(torosPool.address, true);

        const DepositToken = await ethers.getContractAt(
          "@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20",
          assets.usdc,
        );
        await DepositToken.approve(flashSwapperTest.address, depositAmount);
        // Test
        await expect(
          flashSwapperTest.flashSwap(dhedgeEasySwapper.address, torosPool.address, assets.usdc, depositAmount),
        ).to.be.revertedWith("cooldown active");
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
        const torosPool = await ethers.getContractAt("PoolLogic", BASE_TEST_POOL);
        await dhedgeEasySwapper.setPoolAllowed(torosPool.address, true);

        const DepositToken = await ethers.getContractAt(
          "@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20",
          assets.usdc,
        );
        await DepositToken.approve(flashSwapperTest.address, depositAmount);
        // Test
        await expect(
          flashSwapperTest.flashSwapDirectWithdraw(
            dhedgeEasySwapper.address,
            torosPool.address,
            assets.usdc,
            depositAmount,
          ),
        ).to.be.revertedWith("can withdraw shortly");
      });
    });

    describe("Not using the swapper", () => {
      it("24 hour lock up still works", async () => {
        /// NOTE we operate as user1.address in this test so that we don't trigger wallet cooldown for other tests
        // Setup
        const depositAmount = units(1, 6);
        await getAccountToken(depositAmount, user1.address, assets.usdc, assetsBalanceOfSlot.usdc);
        const torosPool = await ethers.getContractAt("PoolLogic", BASE_TEST_POOL);
        const DepositToken = await ethers.getContractAt(
          "@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20",
          assets.usdc,
        );
        await DepositToken.connect(user1).approve(torosPool.address, depositAmount);

        // Deposit
        torosPool.connect(user1).deposit(assets.usdc, depositAmount);
        const balance = await torosPool.connect(user1).balanceOf(user1.address);
        // Withdraw
        await ethers.provider.send("evm_increaseTime", [3600]); // 1 hour
        await ethers.provider.send("evm_mine", []);
        await expect(torosPool.connect(user1).withdraw(balance)).to.be.revertedWith("cooldown active");
      });
    });

    describe("   using swapper for withdraw", () => {
      it("can't withdraw locked tokens via easySwapper", async () => {
        // Setup
        const depositAmount = units(1, 6);
        await getAccountToken(depositAmount, user1.address, assets.usdc, assetsBalanceOfSlot.usdc);
        const torosPool = await ethers.getContractAt("PoolLogic", BASE_TEST_POOL);
        const DepositToken = await ethers.getContractAt(
          "@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20",
          assets.usdc,
        );
        await DepositToken.connect(user1).approve(torosPool.address, depositAmount);
        // Deposit
        await torosPool.connect(user1).deposit(assets.usdc, depositAmount);
        const balance = await torosPool.balanceOf(user1.address);
        // Withdraw
        await ethers.provider.send("evm_increaseTime", [3600]); // 1 hour
        await ethers.provider.send("evm_mine", []);
        await torosPool.connect(user1).approve(dhedgeEasySwapper.address, balance);
        await expect(
          dhedgeEasySwapper.connect(user1).withdraw(torosPool.address, user1.address, assets.usdc, 0),
        ).to.be.revertedWith("cooldown active");
      });
    });

    describe("Using Swapper for deposit", () => {
      it("tokens have lockup", async () => {
        // Setup
        const depositAmount = units(1, 6);
        await getAccountToken(depositAmount, user1.address, assets.usdc, assetsBalanceOfSlot.usdc);
        const torosPool = await ethers.getContractAt("PoolLogic", BASE_TEST_POOL);
        const DepositToken = await ethers.getContractAt(
          "@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20",
          assets.usdc,
        );
        await DepositToken.connect(user1).approve(dhedgeEasySwapper.address, depositAmount);
        // Deposit via EZSwapper
        await dhedgeEasySwapper.connect(user1).deposit(BASE_TEST_POOL, assets.usdc, depositAmount, assets.usdc, 0);
        const balance = await torosPool.balanceOf(user1.address);
        expect(balance.gt(0)).to.equal(true);
        // Deposit via EZSwapper
        await torosPool.connect(user1).approve(dhedgeEasySwapper.address, balance);
        await expect(
          dhedgeEasySwapper.connect(user1).withdraw(torosPool.address, user1.address, assets.usdc, 0),
        ).to.be.revertedWith("cooldown active");
        await expect(torosPool.connect(user1).withdraw(balance)).to.be.revertedWith("cooldown active");
      });
    });

    describe("Multiple users can use swapper at the same time", () => {
      it("2 users deposit, wait, withdraw", async () => {
        const userDepositToken = assets.usdc;
        const userDepositTokenSlot = assetsBalanceOfSlot.usdc;
        const poolDepositToken = assets.usdc;
        const withdrawToken = assets.usdc;
        const torosPool = await ethers.getContractAt("PoolLogic", BASE_TEST_POOL);
        await dhedgeEasySwapper.setPoolAllowed(torosPool.address, true);

        const DepositToken = await ethers.getContractAt(
          "@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20",
          assets.usdc,
        );
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
        await ethers.provider.send("evm_mine", []);

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
        const torosPool = await ethers.getContractAt("PoolLogic", BASE_TEST_POOL);
        await dhedgeEasySwapper.setPoolAllowed(torosPool.address, true);

        const DepositToken = await ethers.getContractAt(
          "@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20",
          assets.usdc,
        );
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
        await ethers.provider.send("evm_mine", []);
        await torosPool.connect(user2).approve(dhedgeEasySwapper.address, balanceUser2);
        await dhedgeEasySwapper.connect(user2).withdraw(torosPool.address, balanceUser2, withdrawToken, 0);
      });
    });

    describe("depositQuote", () => {
      it("provides accurate quote when not swapping", async () => {
        const userDepositToken = assets.usdc;
        const userDepositAmount = units(1000, 1);
        const userDepositSlot = assetsBalanceOfSlot.usdc;
        const poolDepositToken = assets.usdc;

        const dhedgePool = await ethers.getContractAt("PoolLogic", BASE_TEST_POOL);
        const tokenPriceInUSDC = await dhedgePool.tokenPrice();

        const PoolManagerLogic = await ethers.getContractFactory("PoolManagerLogic");
        const poolManagerLogicProxy: PoolManagerLogic = PoolManagerLogic.attach(await dhedgePool.poolManagerLogic());
        const depositAssetValueInUSDC = await poolManagerLogicProxy["assetValue(address,uint256)"](
          userDepositToken,
          userDepositAmount,
        );

        const expectedTokens = depositAssetValueInUSDC.mul(units(1)).div(tokenPriceInUSDC.toString());

        const quote = await dhedgeEasySwapper.depositQuote(
          dhedgePool.address,
          userDepositToken,
          userDepositAmount,
          poolDepositToken,
        );

        expect(quote).to.be.closeTo(expectedTokens, expectedTokens.div(100) as unknown as number);

        await dhedgeEasySwapper.setPoolAllowed(dhedgePool.address, true);
        await getAccountToken(userDepositAmount, logicOwner.address, userDepositToken, userDepositSlot);
        const DepositToken = await ethers.getContractAt(
          "@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20",
          userDepositToken,
        );
        await DepositToken.approve(dhedgeEasySwapper.address, userDepositAmount);
        await dhedgeEasySwapper.deposit(dhedgePool.address, userDepositToken, userDepositAmount, poolDepositToken, 0);

        checkAlmostSame(await dhedgePool.balanceOf(logicOwner.address), quote, 0.0001);
      });

      it("provides accurate quote when swapping", async () => {
        const userDepositToken = assets.weth;
        const userDepositAmount = units(1);
        const userDepositSlot = assetsBalanceOfSlot.weth;
        const poolDepositToken = assets.usdc;

        const dhedgePool = await ethers.getContractAt("PoolLogic", BASE_TEST_POOL);
        const tokenPrice = await dhedgePool.tokenPrice();

        const PoolManagerLogic = await ethers.getContractFactory("PoolManagerLogic");
        const poolManagerLogicProxy: PoolManagerLogic = PoolManagerLogic.attach(await dhedgePool.poolManagerLogic());
        const depositAssetValue = await poolManagerLogicProxy["assetValue(address,uint256)"](
          userDepositToken,
          userDepositAmount,
        );

        const expectedTokens = depositAssetValue.mul(units(1)).div(tokenPrice);
        const quote = await dhedgeEasySwapper.depositQuote(
          dhedgePool.address,
          userDepositToken,
          userDepositAmount,
          poolDepositToken,
        );
        expect(quote).to.be.closeTo(expectedTokens, expectedTokens.div(100) as unknown as number);

        // 5%
        await dhedgeEasySwapper.setFee(50, 1000); // 5%

        const quoteAfterSetFees = await dhedgeEasySwapper.depositQuote(
          dhedgePool.address,
          userDepositToken,
          userDepositAmount,
          poolDepositToken,
        );

        checkAlmostSame(quoteAfterSetFees, quote.mul(95).div(100), 0.001);

        // Deposit with EasySwapper
        await dhedgeEasySwapper.setPoolAllowed(dhedgePool.address, true);
        await getAccountToken(userDepositAmount, logicOwner.address, userDepositToken, userDepositSlot);
        const DepositToken = await ethers.getContractAt(
          "@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20",
          userDepositToken,
        );
        await DepositToken.connect(logicOwner).approve(dhedgeEasySwapper.address, userDepositAmount);
        await dhedgeEasySwapper
          .connect(logicOwner)
          .deposit(dhedgePool.address, userDepositToken, userDepositAmount, poolDepositToken, 0);

        checkAlmostSame(await dhedgePool.balanceOf(logicOwner.address), quoteAfterSetFees, 0.0001);
      });

      it("provides accurate quote for new empty pool", async () => {
        const userDepositToken = assets.weth;
        const userDepositAmount = units(1);
        const poolDepositToken = assets.weth;

        const dhedgePool = await ethers.getContractAt("PoolLogic", emptyNeverFundedDhedgePoolMustAcceptWETH);

        const poolManagerLogic = await ethers.getContractFactory("PoolManagerLogic");
        const poolManagerLogicProxy: PoolManagerLogic = poolManagerLogic.attach(await dhedgePool.poolManagerLogic());
        const depositAssetValue = await poolManagerLogicProxy["assetValue(address,uint256)"](
          userDepositToken,
          userDepositAmount,
        );

        const expectedTokens = depositAssetValue.mul(units(1));
        const quoteWithNonZeroAmount = await dhedgeEasySwapper.depositQuote(
          dhedgePool.address,
          userDepositToken,
          userDepositAmount,
          poolDepositToken,
        );
        expect(quoteWithNonZeroAmount).to.equal(expectedTokens);

        const quoteZeroAmount = await dhedgeEasySwapper.depositQuote(
          dhedgePool.address,
          userDepositToken,
          0,
          poolDepositToken,
        );
        expect(quoteZeroAmount).to.equal(0);
      });
    });

    describe("Real Pool Withdraw Tests", () => {
      const createTestNormal = (test: EasySwapperTestCase, func: "withdraw" | "withdrawSUSD") => {
        const {
          testName,
          dhedgePoolAddress: torosPoolAddress,
          userDepositToken,
          userDepositTokenSlot,
          depositAmount,
          withdrawToken,
          poolDepositToken,
        } = test;
        it(func + ": " + testName, async () => {
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
          const DepositToken = await ethers.getContractAt(
            "@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20",
            userDepositToken,
          );
          await getAccountToken(depositAmount, logicOwner.address, userDepositToken, userDepositTokenSlot);
          expect(await DepositToken.balanceOf(logicOwner.address)).to.equal(depositAmount);
          await DepositToken.approve(dhedgeEasySwapper.address, depositAmount);
          // deposit the cost of 1 token
          await dhedgeEasySwapper.deposit(
            torosPool.address,
            userDepositToken,
            depositAmount,
            poolDepositToken,
            // 3% slippage
            expectedTokens.div(100).mul(97),
          );
          // Make sure we received very close to one token
          const balance = await torosPool.balanceOf(logicOwner.address);
          expect(balance).to.be.closeTo(expectedTokens, expectedTokens.div(100) as unknown as number);
          expect(await DepositToken.balanceOf(logicOwner.address)).to.equal(0);
          await ethers.provider.send("evm_increaseTime", [60 * 6]); // 6 minutes
          await ethers.provider.send("evm_mine", []);
          // Withdraw all

          const actualWithdrawToken = func == "withdraw" ? withdrawToken : assets.susd || "";
          await torosPool.approve(dhedgeEasySwapper.address, balance);
          const WithdrawToken = await ethers.getContractAt(
            "@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20",
            actualWithdrawToken,
          );
          const beforeFundsReturnedBalance = await WithdrawToken.balanceOf(logicOwner.address);
          // Here I need update this to calculate the withdrawal amount out in withdraw token
          await dhedgeEasySwapper[func](torosPool.address, balance, withdrawToken, 0);
          // All tokens were withdrawn
          const balanceAfterWithdraw = await torosPool.balanceOf(logicOwner.address);
          expect(balanceAfterWithdraw).to.equal(0);
          // Check we received back funds close to the value of what we deposited
          const afterFundsReturnedBalance = await WithdrawToken.balanceOf(logicOwner.address);
          const fundsReturned = afterFundsReturnedBalance.sub(beforeFundsReturnedBalance);
          const withdrawAmountUSDC = await poolManagerLogicProxy["assetValue(address,uint256)"](
            actualWithdrawToken,
            fundsReturned,
          );
          // Funds returned should be close to funds in
          const difference = depositAssetValueInUSDC.div(depositAssetValueInUSDC.sub(withdrawAmountUSDC));
          console.log("Total in out Slippage %", 100 / difference.toNumber());
          if (userDepositToken === actualWithdrawToken) {
            if (fundsReturned > depositAmount) {
              console.log("Returned amount is more than deposit amount");
            }
          }
          // Funds returned should be close to funds in
          expect(withdrawAmountUSDC).closeTo(
            depositAssetValueInUSDC,
            // 3% - in and out slippage is quite a bit 605570-595902
            depositAssetValueInUSDC.div(100).mul(3) as unknown as number,
          );
        });
      };
      const createTestNative = (test: EasySwapperNativeTestCase) => {
        const { testName, dhedgePoolAddress: torosPoolAddress, nativeAssetDepositAmount, poolDepositToken } = test;
        it("[native-asset] " + testName, async () => {
          const torosPool = await ethers.getContractAt("PoolLogic", torosPoolAddress);
          await dhedgeEasySwapper.setPoolAllowed(torosPool.address, true);
          // Reset token ownership - for when other tests fail
          // TokenPrice is in 10**18
          const tokenPriceInUSD = await torosPool.tokenPrice();
          const PoolManagerLogic = await ethers.getContractFactory("PoolManagerLogic");
          const poolManagerLogicProxy: PoolManagerLogic = await PoolManagerLogic.attach(
            await torosPool.poolManagerLogic(),
          );
          const depositAssetValueInUSD = await poolManagerLogicProxy["assetValue(address,uint256)"](
            nativeAssetWrapper,
            nativeAssetDepositAmount,
          );
          console.log("depositAssetValueInUSD $", depositAssetValueInUSD.div(units(1)).toString());
          console.log("totalFundValue $", (await poolManagerLogicProxy.totalFundValue()).div(units(1)).toString());
          const expectedTokens = depositAssetValueInUSD.mul(units(1)).div(tokenPriceInUSD.toString());
          // deposit the cost of 1 token
          await dhedgeEasySwapper.depositNative(
            torosPool.address,
            poolDepositToken,
            // 3% slippage
            expectedTokens.div(100).mul(97),
            {
              value: nativeAssetDepositAmount,
            },
          );
          // Make sure we received very close to one token
          const balance = await torosPool.balanceOf(logicOwner.address);
          expect(balance).to.be.closeTo(expectedTokens, expectedTokens.div(100) as unknown as number);
          await ethers.provider.send("evm_increaseTime", [60 * 6]); // 6 minutes
          await ethers.provider.send("evm_mine", []);
          // Withdraw all
          await torosPool.approve(dhedgeEasySwapper.address, balance);
          const beforeFundsReturnedBalance = await logicOwner.getBalance();
          // Here I need update this to calculate the withdrawal amount out in withdraw token
          const txResult = await (await dhedgeEasySwapper.withdrawNative(torosPool.address, balance, 0)).wait();
          // Calculate transaction fee for correct withdrawn amount of native asset
          const txFee = txResult.cumulativeGasUsed.mul(txResult.effectiveGasPrice);

          // All tokens were withdrawn
          const balanceAfterWithdraw = await torosPool.balanceOf(logicOwner.address);
          expect(balanceAfterWithdraw).to.equal(0);
          // Check we received back funds close to the value of what we deposited
          const afterFundsReturnedBalance = await logicOwner.getBalance();
          // Subtract transaction fee
          const fundsReturned = afterFundsReturnedBalance.add(txFee).sub(beforeFundsReturnedBalance);
          const withdrawAmountUSD = await poolManagerLogicProxy["assetValue(address,uint256)"](
            nativeAssetWrapper,
            fundsReturned,
          );
          // Funds returned should be close to funds in
          const difference = depositAssetValueInUSD.div(depositAssetValueInUSD.sub(withdrawAmountUSD));
          console.log("Total in out Slippage %", 100 / difference.toNumber());

          // Funds returned should be close to funds in
          expect(withdrawAmountUSD).closeTo(
            depositAssetValueInUSD,
            // 3% - in and out slippage is quite a bit 605570-595902
            depositAssetValueInUSD.div(100).mul(3) as unknown as number,
          );
        });
      };

      withdrawNormalTestCases.forEach((testCase) => createTestNormal(testCase, "withdraw"));
      withdrawSUSDTestCases.forEach((testCase) => createTestNormal(testCase, "withdrawSUSD"));
      withdrawNativeTestCases.forEach(createTestNative);
    });
  });
};
