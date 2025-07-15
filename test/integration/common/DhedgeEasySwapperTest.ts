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
import { checkAlmostSame, units } from "../../testHelpers";
import { getAccountToken } from "../utils/getAccountTokens";

import { utils } from "../utils/utils";
import { createFund } from "../utils/createFund";
import { Address } from "../../../deployment/types";
import { AssetType } from "../../../deployment/upgrade/jobs/assetsJob";

const SKIP_TIME = 60 * 61; // 1 hour and 1 second

export interface EasySwapperTestCase {
  testName: string;
  dhedgePoolAddress: string;
  poolDepositToken: string;
  userDepositToken: string;
  userDepositTokenSlot: number;
  withdrawToken: string;
  depositAmount: BigNumber;
  nativeAssetDepositAmount: BigNumber;
}

interface EasySwapperTestsChainData {
  assets: {
    weth: string;
    usdc: string;
    dai: string;
    susd?: string;
    snxProxy?: string;
  };
  assetsBalanceOfSlot: {
    usdc: number;
    weth: number;
  };
  v2Routers: string[];
  uniswapV3: {
    factory: string;
    router: string;
  };
  velodromeV2?: {
    router: string;
    factory: string;
  };
  ramses?: {
    router: string;
  };
  proxyAdmin: string;
  routeHints: { asset: string; intermediary: string }[];
  aaveV3: {
    protocolDataProvider: string;
    lendingPool: string;
  };
  flatMoney: { swapper: string };
}

export const DhedgeEasySwapperTests = (
  poolFactoryProxy: string,
  baseTestDhedgePoolMustAcceptUSDC: Address,
  testCases: EasySwapperTestCase[],
  withdrawSUSDTestCases: EasySwapperTestCase[],
  chainData: EasySwapperTestsChainData,
  nativeAssetWrapper: Address,
  emptyNeverFundedDhedgePoolMustAcceptWETH: Address,
) => {
  const { assets, assetsBalanceOfSlot, v2Routers, uniswapV3, velodromeV2, routeHints, ramses, aaveV3 } = chainData;
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
      poolFactory.connect(poolFactoryOwner).setMaximumFee(5000, 300, 100, 100);
      poolFactory.connect(poolFactoryOwner).setPerformanceFeeNumeratorChangeDelay(0);

      const DhedgeUniV3V2Router = await ethers.getContractFactory("DhedgeUniV3V2Router");
      const dhedgeUniV3V2Router = await DhedgeUniV3V2Router.deploy(uniswapV3.factory, uniswapV3.router);
      await dhedgeUniV3V2Router.deployed();

      if (velodromeV2) {
        const DhedgeVeloV2UniV2Router = await ethers.getContractFactory("DhedgeVeloV2UniV2Router");
        const dhedgeVeloV2UniV2Router = await DhedgeVeloV2UniV2Router.deploy(velodromeV2.router, velodromeV2.factory);
        await dhedgeVeloV2UniV2Router.deployed();
        v2Routers.push(dhedgeVeloV2UniV2Router.address);
      }

      if (ramses) {
        const DhedgeRamsesUniV2Router = await ethers.getContractFactory("DhedgeRamsesUniV2Router");
        const dhedgeRamsesUniV2Router = await DhedgeRamsesUniV2Router.deploy(ramses.router);
        await dhedgeRamsesUniV2Router.deployed();
        v2Routers.push(dhedgeRamsesUniV2Router.address);
      }

      const DHedgePoolAggregator = await ethers.getContractFactory("DHedgePoolAggregator");
      const dHedgePoolAggregator = await DHedgePoolAggregator.deploy(BASE_TEST_POOL);
      await dHedgePoolAggregator.deployed();

      const SwapRouter = await ethers.getContractFactory("DhedgeSuperSwapper");
      const swapRouter = await SwapRouter.deploy([dhedgeUniV3V2Router.address, ...v2Routers], routeHints);
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
        synthetixProps: {
          swapSUSDToAsset: assets.dai,
          sUSDProxy: assets.susd || ethers.constants.AddressZero,
          snxProxy: assets.snxProxy || ethers.constants.AddressZero,
        },
        nativeAssetWrapper,
      });

      const assetHandler = await ethers.getContractAt("AssetHandler", await poolFactory.getAssetHandler());

      const assetHandlerOwner = await utils.impersonateAccount(await assetHandler.owner());
      assetHandler.connect(assetHandlerOwner).addAssets([
        {
          asset: BASE_TEST_POOL, // enables Toros pool as an asset
          assetType: AssetType["Chainlink direct USD price feed with 8 decimals"],
          aggregator: dHedgePoolAggregator.address,
        },
      ]);

      governance = await ethers.getContractAt(
        "Governance",
        await poolFactory.connect(poolFactoryOwner).governanceAddress(),
      );

      const govSigner = await utils.impersonateAccount(await governance.owner());
      await governance
        .connect(govSigner)
        .setAssetGuard(
          AssetType["Synthetix synth with Chainlink direct USD price feed"],
          await governance.assetGuards(0),
        );
      await governance.connect(govSigner).setContractGuard(dhedgeEasySwapper.address, easySwapperGuard.address);
      const AaveLendingPoolAssetGuard = await ethers.getContractFactory("AaveLendingPoolAssetGuard");
      const aaveLendingPoolAssetGuard = await AaveLendingPoolAssetGuard.deploy(
        aaveV3.protocolDataProvider,
        aaveV3.lendingPool,
        chainData.flatMoney.swapper,
        swapRouter.address,
        5,
        10_000,
        10_000,
      );
      await aaveLendingPoolAssetGuard.deployed();
      await governance
        .connect(govSigner)
        .setAssetGuard(AssetType["Aave V3 Lending Pool Asset"], aaveLendingPoolAssetGuard.address);

      await dhedgeEasySwapper.setFee(0, 0);

      await poolFactory.connect(poolFactoryOwner).addCustomCooldownWhitelist(dhedgeEasySwapper.address);
      expect(await poolFactory.connect(poolFactoryOwner).customCooldownWhitelist(dhedgeEasySwapper.address)).to.be.true;
    });

    describe("Fees", () => {
      it("fee sink receives fee after custom cooldown deposit", async () => {
        const depositAmount = units(6, 6); // Amount should be greater than 5e6.
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
        await dhedgeEasySwapper.depositWithCustomCooldown(BASE_TEST_POOL, assets.usdc, depositAmount, assets.usdc, 0);
        // Fee of 1% received by fee sink
        const balanceAfter = await DepositToken.balanceOf(feeSink.address);
        expect(balanceAfter.sub(balanceBefore)).to.equal(depositAmount.div(100));
        await dhedgeEasySwapper.setFee(0, 0);
      });

      it("pool manager fee bypass works with custom cooldown deposit", async () => {
        // Invest into Toros pool from a manager pool
        // The manager is whitelisted to bypass fee
        const DepositToken = await ethers.getContractAt(
          "@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20",
          assets.usdc,
        );
        const depositAmount = units(6, 6);
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
        const easySwapperDepositData = dhedgeEasySwapperAbi.encodeFunctionData("depositWithCustomCooldown", [
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

      it("doesn't receive fee if pool has entry fee set up", async () => {
        const { poolLogicProxy, poolManagerLogicProxy } = await createFund(poolFactory, logicOwner, user1, [
          { asset: assets.usdc, isDeposit: true },
        ]);
        await dhedgeEasySwapper.setFee(1, 100); // 1%
        await dhedgeEasySwapper.setPoolAllowed(poolLogicProxy.address, true);
        await poolManagerLogicProxy.connect(user1).announceFeeIncrease(5000, 0, 100, 100); // 1% entry fee, 1% exit fee
        await poolManagerLogicProxy.connect(user1).commitFeeIncrease();

        const depositAmount = units(10, 6); // 10 USDC
        await getAccountToken(depositAmount, user1.address, assets.usdc, assetsBalanceOfSlot.usdc);

        const DepositToken = await ethers.getContractAt(
          "@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20",
          assets.usdc,
        );
        const sinkBalanceBefore = await DepositToken.balanceOf(feeSink.address);
        expect(sinkBalanceBefore).to.equal(0);
        await DepositToken.connect(user1).approve(dhedgeEasySwapper.address, depositAmount);
        await dhedgeEasySwapper
          .connect(user1)
          .depositWithCustomCooldown(poolLogicProxy.address, assets.usdc, depositAmount, assets.usdc, 0);
        const sinkBalanceAfter = await DepositToken.balanceOf(feeSink.address);
        expect(sinkBalanceAfter).to.equal(0);
      });
    });

    describe("FlashSwap Test", () => {
      it("cannot deposit and withdraw in one block", async () => {
        // Setup
        const FlashSwapperTest = await ethers.getContractFactory("FlashSwapperTest");
        const flashSwapperTest = await FlashSwapperTest.deploy();
        await flashSwapperTest.deployed();
        const depositAmount = units(6, 6);
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
        const depositAmount = units(6, 6);
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
        ).to.be.revertedWith("can withdraw soon");
      });
    });

    describe("Not using the swapper", () => {
      it("24 hour lock up still works", async () => {
        /// NOTE we operate as user1.address in this test so that we don't trigger wallet cooldown for other tests
        // Setup
        const depositAmount = units(6, 6);
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

    describe("Using swapper for withdraw", () => {
      it("can't withdraw locked tokens via easySwapper", async () => {
        // Setup
        const depositAmount = units(6, 6);
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
        const depositAmount = units(6, 6);
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

      it("doesn't allow to call custom cooldown deposit methods for non-allowed pools", async () => {
        const depositAmount = units(6, 6);
        await getAccountToken(depositAmount, logicOwner.address, assets.usdc, assetsBalanceOfSlot.usdc);
        const DepositToken = await ethers.getContractAt(
          "@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20",
          assets.usdc,
        );
        await DepositToken.approve(dhedgeEasySwapper.address, depositAmount);
        await expect(
          dhedgeEasySwapper.depositWithCustomCooldown(BASE_TEST_POOL, assets.usdc, depositAmount, assets.usdc, 0),
        ).to.be.revertedWith("no-go");
        await expect(
          dhedgeEasySwapper.depositNativeWithCustomCooldown(BASE_TEST_POOL, assets.usdc, 0, {
            value: units(1),
          }),
        ).to.be.revertedWith("no-go");
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
        const depositAmount = units(6, 6);

        await getAccountToken(depositAmount, logicOwner.address, userDepositToken, userDepositTokenSlot);
        await getAccountToken(depositAmount, user2.address, userDepositToken, userDepositTokenSlot);

        expect(await DepositToken.balanceOf(logicOwner.address)).to.equal(depositAmount);
        expect(await DepositToken.balanceOf(user2.address)).to.equal(depositAmount);

        await DepositToken.approve(dhedgeEasySwapper.address, depositAmount);
        await DepositToken.connect(user2).approve(dhedgeEasySwapper.address, depositAmount);

        await dhedgeEasySwapper.depositWithCustomCooldown(
          torosPool.address,
          userDepositToken,
          depositAmount,
          poolDepositToken,
          0,
        );
        await dhedgeEasySwapper
          .connect(user2)
          .depositWithCustomCooldown(torosPool.address, userDepositToken, depositAmount, poolDepositToken, 0);

        const balanceLogicOwner = await torosPool.balanceOf(logicOwner.address);
        const balanceUser2 = await torosPool.balanceOf(user2.address);

        await ethers.provider.send("evm_increaseTime", [SKIP_TIME]);
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
        const depositAmount = units(6, 6);

        await getAccountToken(depositAmount, logicOwner.address, userDepositToken, userDepositTokenSlot);
        await getAccountToken(depositAmount, user2.address, userDepositToken, userDepositTokenSlot);

        expect(await DepositToken.balanceOf(logicOwner.address)).to.equal(depositAmount);
        expect(await DepositToken.balanceOf(user2.address)).to.equal(depositAmount);

        await DepositToken.approve(dhedgeEasySwapper.address, depositAmount);
        await DepositToken.connect(user2).approve(dhedgeEasySwapper.address, depositAmount);

        await dhedgeEasySwapper.depositWithCustomCooldown(
          torosPool.address,
          userDepositToken,
          depositAmount,
          poolDepositToken,
          0,
        );
        const balanceLogicOwner = await torosPool.balanceOf(logicOwner.address);

        await ethers.provider.send("evm_increaseTime", [SKIP_TIME]);

        // Withdraw all
        await dhedgeEasySwapper
          .connect(user2)
          .depositWithCustomCooldown(torosPool.address, userDepositToken, depositAmount, poolDepositToken, 0);
        const balanceUser2 = await torosPool.balanceOf(user2.address);

        await torosPool.approve(dhedgeEasySwapper.address, balanceLogicOwner);
        await dhedgeEasySwapper.withdraw(torosPool.address, balanceLogicOwner, withdrawToken, 0);

        await ethers.provider.send("evm_increaseTime", [SKIP_TIME]);
        await ethers.provider.send("evm_mine", []);
        await torosPool.connect(user2).approve(dhedgeEasySwapper.address, balanceUser2);
        await dhedgeEasySwapper.connect(user2).withdraw(torosPool.address, balanceUser2, withdrawToken, 0);
      });
    });

    describe("depositQuote", () => {
      it("provides accurate quote when not swapping", async () => {
        const userDepositToken = assets.usdc;
        const userDepositAmount = units(1000, 6);
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
          true,
        );

        expect(quote).to.be.closeTo(expectedTokens, expectedTokens.div(100));

        await dhedgeEasySwapper.setPoolAllowed(dhedgePool.address, true);
        await getAccountToken(userDepositAmount, logicOwner.address, userDepositToken, userDepositSlot);
        const DepositToken = await ethers.getContractAt(
          "@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20",
          userDepositToken,
        );
        await DepositToken.approve(dhedgeEasySwapper.address, userDepositAmount);
        await dhedgeEasySwapper.depositWithCustomCooldown(
          dhedgePool.address,
          userDepositToken,
          userDepositAmount,
          poolDepositToken,
          0,
        );

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
          false,
        );
        expect(quote).to.be.closeTo(expectedTokens, expectedTokens.div(100));

        // 5%
        await dhedgeEasySwapper.setFee(50, 1000); // 5%

        const quoteAfterSetFees = await dhedgeEasySwapper.depositQuote(
          dhedgePool.address,
          userDepositToken,
          userDepositAmount,
          poolDepositToken,
          true,
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
          .depositWithCustomCooldown(dhedgePool.address, userDepositToken, userDepositAmount, poolDepositToken, 0);

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
        const quoteWithNonZeroAmount = await dhedgeEasySwapper.depositQuote(
          dhedgePool.address,
          userDepositToken,
          userDepositAmount,
          poolDepositToken,
          false,
        );
        expect(quoteWithNonZeroAmount).to.equal(depositAssetValue);

        const quoteZeroAmount = await dhedgeEasySwapper.depositQuote(
          dhedgePool.address,
          userDepositToken,
          0,
          poolDepositToken,
          false,
        );
        expect(quoteZeroAmount).to.equal(0);
      });

      it("provides accurate quote for pool with entry fee set", async () => {
        const { poolLogicProxy, poolManagerLogicProxy } = await createFund(poolFactory, logicOwner, user1, [
          { asset: assets.usdc, isDeposit: true },
        ]);
        await poolManagerLogicProxy.connect(user1).announceFeeIncrease(5000, 0, 100, 100); // 1% entry fee, 1% exit fee
        await poolManagerLogicProxy.connect(user1).commitFeeIncrease();

        const depositAmount = units(10, 6); // 10 USDC
        const expectedPoolTokens = units(10);
        const quote = await dhedgeEasySwapper.depositQuote(
          poolLogicProxy.address,
          assets.usdc,
          depositAmount,
          assets.usdc,
          false,
        );
        expect(quote).to.be.closeTo(expectedPoolTokens, quote.div(95)); // 1.05% delta
      });
    });

    describe("Real Pool Deposit/Withdraw Tests", () => {
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
            await torosPool.connect(logicOwner).approve(dhedgeEasySwapper.address, balanceBefore);
            await dhedgeEasySwapper.connect(logicOwner).withdraw(torosPool.address, balanceBefore, withdrawToken, 0);
          }
          // TokenPrice is in 10**18
          // But usdc is in 10**6
          // And asset price in 10**18 hurt my brain
          const tokenPriceInUSDC = await torosPool.tokenPrice();
          const PoolManagerLogic = await ethers.getContractFactory("PoolManagerLogic");
          const poolManagerLogicProxy: PoolManagerLogic = PoolManagerLogic.attach(await torosPool.poolManagerLogic());
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
          await DepositToken.connect(logicOwner).approve(dhedgeEasySwapper.address, depositAmount);
          // deposit the cost of 1 token
          await dhedgeEasySwapper.connect(logicOwner).depositWithCustomCooldown(
            torosPool.address,
            userDepositToken,
            depositAmount,
            poolDepositToken,
            // 3% slippage
            expectedTokens.div(100).mul(97),
          );
          // Make sure we received very close to one token
          const balance = await torosPool.balanceOf(logicOwner.address);
          expect(balance).to.be.closeTo(expectedTokens, expectedTokens.div(100));
          expect(await DepositToken.balanceOf(logicOwner.address)).to.equal(0);
          await utils.increaseTime(SKIP_TIME);
          // Withdraw all

          const actualWithdrawToken = func == "withdraw" ? withdrawToken : assets.susd || "";
          await torosPool.connect(logicOwner).approve(dhedgeEasySwapper.address, balance);
          const WithdrawToken = await ethers.getContractAt(
            "@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20",
            actualWithdrawToken,
          );
          const beforeFundsReturnedBalance = await WithdrawToken.balanceOf(logicOwner.address);
          // Here I need update this to calculate the withdrawal amount out in withdraw token
          await dhedgeEasySwapper
            .connect(logicOwner)
            [func](torosPool.address, balance, withdrawToken, 0, { gasLimit: 30000000 });
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
            depositAssetValueInUSDC.div(100).mul(3),
          );
        });
      };
      const createTestNative = (test: EasySwapperTestCase) => {
        const { testName, dhedgePoolAddress: torosPoolAddress, nativeAssetDepositAmount, poolDepositToken } = test;
        it("depositNative " + testName, async () => {
          const torosPool = await ethers.getContractAt("PoolLogic", torosPoolAddress);
          await dhedgeEasySwapper.setPoolAllowed(torosPool.address, true);
          // Reset token ownership - for when other tests fail
          // TokenPrice is in 10**18
          const tokenPriceInUSD = await torosPool.tokenPrice();
          const PoolManagerLogic = await ethers.getContractFactory("PoolManagerLogic");
          const poolManagerLogicProxy: PoolManagerLogic = PoolManagerLogic.attach(await torosPool.poolManagerLogic());
          const depositAssetValueInUSD = await poolManagerLogicProxy["assetValue(address,uint256)"](
            nativeAssetWrapper,
            nativeAssetDepositAmount,
          );
          const expectedTokens = depositAssetValueInUSD.mul(units(1)).div(tokenPriceInUSD.toString());
          // deposit the cost of 1 token
          await dhedgeEasySwapper.connect(logicOwner).depositNativeWithCustomCooldown(
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
          expect(balance).to.be.closeTo(expectedTokens, expectedTokens.div(100));
        });
      };

      testCases.forEach((testCase) => createTestNormal(testCase, "withdraw"));
      withdrawSUSDTestCases.forEach((testCase) => createTestNormal(testCase, "withdrawSUSD"));
      testCases.forEach(createTestNative);
    });
  });
};
