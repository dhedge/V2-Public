import { ethers } from "hardhat";
import { expect } from "chai";
import { checkAlmostSame, units } from "../../../testHelpers";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import {
  IERC20,
  IERC20__factory,
  IVelodromeGauge__factory,
  IVelodromeRouter__factory,
  IVelodromeV2Gauge__factory,
  IVelodromeV2Router__factory,
  PoolFactory,
  PoolLogic,
  PoolManagerLogic,
} from "../../../../types";
import { createFund } from "../../utils/createFund";
import { ovmChainData } from "../../../../config/chainData/ovmData";
import { getAccountToken } from "../../utils/getAccountTokens";
import { deployContracts } from "../../utils/deployContracts/deployContracts";
import { utils } from "../../utils/utils";
import { getGaugeDepositParams, IVeloGauge, getEarnedAmount } from "./helpers";

const { assets, assetsBalanceOfSlot, velodrome, velodromeV2 } = ovmChainData;

type ITestParam = typeof velodromeV2 & {
  gaugeContractName: "IVelodromeGauge" | "IVelodromeV2Gauge";
  routerFactory: typeof IVelodromeRouter__factory | typeof IVelodromeV2Router__factory;
  gaugeFactory: typeof IVelodromeGauge__factory | typeof IVelodromeV2Gauge__factory;
  v2: boolean;
};

const runTests = ({
  router,
  STABLE_USDC_DAI,
  velo,
  gaugeContractName,
  routerFactory,
  gaugeFactory,
  v2,
}: ITestParam) => {
  describe(`VelodromeLPAssetGuard ${v2 ? "V2 " : ""}Test`, () => {
    let USDC: IERC20, DAI: IERC20, VELO: IERC20, VELODROME_USDC_DAI: IERC20, VELODROME_USDC_DAI_GAUGE: IVeloGauge;
    let logicOwner: SignerWithAddress, manager: SignerWithAddress;
    let poolFactory: PoolFactory, poolLogicProxy: PoolLogic, poolManagerLogicProxy: PoolManagerLogic;
    let lpAmount;
    const iERC20 = new ethers.utils.Interface(IERC20__factory.abi);
    const iVelodromeRouter = new ethers.utils.Interface(routerFactory.abi);
    const iVelodromeGauge = new ethers.utils.Interface(gaugeFactory.abi);

    before(async () => {
      [logicOwner, manager] = await ethers.getSigners();
      const deployments = await deployContracts("ovm");
      poolFactory = deployments.poolFactory;

      USDC = <IERC20>await ethers.getContractAt("@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20", assets.usdc);
      DAI = <IERC20>await ethers.getContractAt("@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20", assets.dai);
      VELO = <IERC20>await ethers.getContractAt("@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20", velo);
      VELODROME_USDC_DAI = <IERC20>(
        await ethers.getContractAt("@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20", STABLE_USDC_DAI.poolAddress)
      );
      VELODROME_USDC_DAI_GAUGE = <IVeloGauge>(
        await ethers.getContractAt(gaugeContractName, STABLE_USDC_DAI.gaugeAddress)
      );

      await getAccountToken(units(10000), logicOwner.address, assets.usdc, assetsBalanceOfSlot.usdc);
      await getAccountToken(units(10000), logicOwner.address, assets.dai, assetsBalanceOfSlot.dai);

      const funds = await createFund(poolFactory, logicOwner, manager, [
        { asset: assets.usdc, isDeposit: true },
        { asset: assets.dai, isDeposit: true },
        { asset: STABLE_USDC_DAI.poolAddress, isDeposit: false },
      ]);
      poolLogicProxy = funds.poolLogicProxy;
      poolManagerLogicProxy = funds.poolManagerLogicProxy;

      // Deposit 200 USDC
      await USDC.approve(poolLogicProxy.address, units(200, 6));
      await poolLogicProxy.deposit(assets.usdc, units(200, 6));
      // Deposit 200 DAI
      await DAI.approve(poolLogicProxy.address, units(200));
      await poolLogicProxy.deposit(assets.dai, units(200));

      let approveABI = iERC20.encodeFunctionData("approve", [router, units(200, 6)]);
      await poolLogicProxy.connect(manager).execTransaction(assets.usdc, approveABI);
      approveABI = iERC20.encodeFunctionData("approve", [router, units(200)]);
      await poolLogicProxy.connect(manager).execTransaction(assets.dai, approveABI);
    });

    utils.beforeAfterReset(beforeEach, afterEach);

    describe("withdrawProcessing", () => {
      beforeEach(async () => {
        const addLiquidityTx = iVelodromeRouter.encodeFunctionData("addLiquidity", [
          assets.usdc,
          assets.dai,
          STABLE_USDC_DAI.isStable,
          units(100, 6),
          units(100),
          0,
          0,
          poolLogicProxy.address,
          ethers.constants.MaxUint256,
        ]);
        await poolLogicProxy.connect(manager).execTransaction(router, addLiquidityTx);

        lpAmount = await VELODROME_USDC_DAI.balanceOf(poolLogicProxy.address);

        const approveABI = iERC20.encodeFunctionData("approve", [STABLE_USDC_DAI.gaugeAddress, lpAmount]);
        await poolLogicProxy.connect(manager).execTransaction(STABLE_USDC_DAI.poolAddress, approveABI);

        const depositABI = iVelodromeGauge.encodeFunctionData(...getGaugeDepositParams(lpAmount, v2));
        await poolLogicProxy.connect(manager).execTransaction(STABLE_USDC_DAI.gaugeAddress, depositABI);

        await poolFactory.setExitCooldown(0);
        await ethers.provider.send("evm_increaseTime", [3600 * 24 * 3]); // 3 days
        await ethers.provider.send("evm_mine", []);
      });

      it("Pool has expected funds after withdraw", async () => {
        const usdcBalanceBefore = await USDC.balanceOf(poolLogicProxy.address);
        const daiBalanceBefore = await DAI.balanceOf(poolLogicProxy.address);
        const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();
        const gaugeBalanceBefore = await VELODROME_USDC_DAI_GAUGE.balanceOf(poolLogicProxy.address);

        // withdraw half
        await poolLogicProxy.withdraw((await poolLogicProxy.balanceOf(logicOwner.address)).div(2));

        // includes additional rewards, hence 0.05% threshold
        checkAlmostSame(await USDC.balanceOf(poolLogicProxy.address), usdcBalanceBefore.div(2), 0.05); // includes additional rewards, hence 0.05% threshold
        checkAlmostSame(await DAI.balanceOf(poolLogicProxy.address), daiBalanceBefore.div(2), 0.05); // includes additional rewards, hence 0.05% threshold
        checkAlmostSame(await poolManagerLogicProxy.totalFundValue(), totalFundValueBefore.div(2), 0.05); // includes additional rewards, hence 0.05% threshold
        checkAlmostSame(
          await VELODROME_USDC_DAI_GAUGE.balanceOf(poolLogicProxy.address),
          gaugeBalanceBefore.div(2),
          0.05,
        );
      });

      it("Pool receives expected rewards", async () => {
        const claimAmount = await getEarnedAmount(VELODROME_USDC_DAI_GAUGE, poolLogicProxy.address, VELO.address);
        expect(claimAmount).to.gt(0);

        // withdraw half
        await poolLogicProxy.withdraw((await poolLogicProxy.balanceOf(logicOwner.address)).div(2));

        checkAlmostSame(await VELO.balanceOf(poolLogicProxy.address), claimAmount.div(2), 0.05);
      });

      it("Withdrawer receives their portion of LP Tokens and Rewards", async () => {
        const claimAmount = await getEarnedAmount(VELODROME_USDC_DAI_GAUGE, poolLogicProxy.address, VELO.address);
        expect(claimAmount).to.gt(0);

        // withdraw half
        await poolLogicProxy.withdraw((await poolLogicProxy.balanceOf(logicOwner.address)).div(2));
        checkAlmostSame(await VELODROME_USDC_DAI.balanceOf(logicOwner.address), lpAmount.div(2), 0.05);
        checkAlmostSame(await VELO.balanceOf(logicOwner.address), claimAmount.div(2), 0.05);
      });
    });

    describe("getBalance", () => {
      it("Prices underlying LP token correctly", async () => {
        let totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

        const addLiquidityTx = iVelodromeRouter.encodeFunctionData("addLiquidity", [
          assets.usdc,
          assets.dai,
          STABLE_USDC_DAI.isStable,
          units(100, 6),
          units(100),
          0,
          0,
          poolLogicProxy.address,
          ethers.constants.MaxUint256,
        ]);
        await poolLogicProxy.connect(manager).execTransaction(router, addLiquidityTx);

        // price change between chainlink & amm, threshold
        checkAlmostSame(await poolManagerLogicProxy.totalFundValue(), totalFundValueBefore, 0.05);

        lpAmount = await VELODROME_USDC_DAI.balanceOf(poolLogicProxy.address);

        totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();
        const usdcBalanceBefore = await USDC.balanceOf(poolLogicProxy.address);
        const daiBalanceBefore = await DAI.balanceOf(poolLogicProxy.address);

        const approveABI = iERC20.encodeFunctionData("approve", [STABLE_USDC_DAI.gaugeAddress, lpAmount]);
        await poolLogicProxy.connect(manager).execTransaction(STABLE_USDC_DAI.poolAddress, approveABI);

        const depositABI = iVelodromeGauge.encodeFunctionData(...getGaugeDepositParams(lpAmount.div(2), v2));
        await poolLogicProxy.connect(manager).execTransaction(STABLE_USDC_DAI.gaugeAddress, depositABI);

        expect(await VELODROME_USDC_DAI.balanceOf(poolLogicProxy.address)).to.be.closeTo(lpAmount.div(2), 1);
        expect(await USDC.balanceOf(poolLogicProxy.address)).to.be.eq(usdcBalanceBefore);
        expect(await DAI.balanceOf(poolLogicProxy.address)).to.be.eq(daiBalanceBefore);
        expect(await poolManagerLogicProxy.totalFundValue()).to.equal(totalFundValueBefore);
      });

      it("Includes unclaimed rewards in Price", async () => {
        const addLiquidityTx = iVelodromeRouter.encodeFunctionData("addLiquidity", [
          assets.usdc,
          assets.dai,
          STABLE_USDC_DAI.isStable,
          units(100, 6),
          units(100),
          0,
          0,
          poolLogicProxy.address,
          ethers.constants.MaxUint256,
        ]);
        await poolLogicProxy.connect(manager).execTransaction(router, addLiquidityTx);

        lpAmount = await VELODROME_USDC_DAI.balanceOf(poolLogicProxy.address);

        const approveABI = iERC20.encodeFunctionData("approve", [STABLE_USDC_DAI.gaugeAddress, lpAmount]);
        await poolLogicProxy.connect(manager).execTransaction(STABLE_USDC_DAI.poolAddress, approveABI);

        const depositABI = iVelodromeGauge.encodeFunctionData(...getGaugeDepositParams(lpAmount, v2));
        await poolLogicProxy.connect(manager).execTransaction(STABLE_USDC_DAI.gaugeAddress, depositABI);

        const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

        await ethers.provider.send("evm_increaseTime", [3600 * 24]);
        await ethers.provider.send("evm_mine", []);

        const claimAmount = await getEarnedAmount(VELODROME_USDC_DAI_GAUGE, poolLogicProxy.address, VELO.address);
        expect(claimAmount).to.gt(0);
        expect(await poolManagerLogicProxy.totalFundValue()).to.closeTo(
          totalFundValueBefore.add(
            await poolManagerLogicProxy["assetValue(address,uint256)"](VELO.address, claimAmount),
          ),
          await poolManagerLogicProxy["assetValue(address,uint256)"](VELO.address, claimAmount.div(1000)),
        );
      });
    });
  });
};

[
  {
    ...velodrome,
    gaugeContractName: "IVelodromeGauge" as const,
    routerFactory: IVelodromeRouter__factory,
    gaugeFactory: IVelodromeGauge__factory,
    v2: false,
  },
  {
    ...velodromeV2,
    gaugeContractName: "IVelodromeV2Gauge" as const,
    routerFactory: IVelodromeV2Router__factory,
    gaugeFactory: IVelodromeV2Gauge__factory,
    v2: true,
  },
].forEach(runTests);
