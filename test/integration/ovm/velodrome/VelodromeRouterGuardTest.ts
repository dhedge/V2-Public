import { ethers } from "hardhat";
import { expect } from "chai";
import { units } from "../../../testHelpers";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import {
  IERC20,
  IERC20__factory,
  IVelodromeRouter__factory,
  IVelodromeV2Router__factory,
  PoolFactory,
  PoolLogic,
} from "../../../../types";
import { createFund } from "../../utils/createFund";
import { ovmChainData } from "../../../../config/chainData/ovmData";
import { getAccountToken } from "../../utils/getAccountTokens";
import { deployContracts } from "../../utils/deployContracts/deployContracts";
import { utils } from "../../utils/utils";

const { assets, assetsBalanceOfSlot, velodrome, velodromeV2 } = ovmChainData;

type ITestParam = typeof velodromeV2 & {
  routerFactory: typeof IVelodromeRouter__factory | typeof IVelodromeV2Router__factory;
};

const runTests = ({ STABLE_USDC_DAI, router, VARIABLE_WETH_USDC, routerFactory }: ITestParam) => {
  describe("Velodrome Router Guard Test", function () {
    let USDC: IERC20, DAI: IERC20, VELODROME_USDC_DAI: IERC20;
    let logicOwner: SignerWithAddress, manager: SignerWithAddress, userNotPool: SignerWithAddress;
    let poolFactory: PoolFactory, poolLogicProxy: PoolLogic;
    let lpAmount;
    const iERC20 = new ethers.utils.Interface(IERC20__factory.abi);
    const iVelodromeRouter = new ethers.utils.Interface(routerFactory.abi);

    before(async function () {
      [logicOwner, manager, userNotPool] = await ethers.getSigners();
      const deployments = await deployContracts("ovm");
      poolFactory = deployments.poolFactory;

      USDC = <IERC20>await ethers.getContractAt("@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20", assets.usdc);
      DAI = <IERC20>await ethers.getContractAt("@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20", assets.dai);
      VELODROME_USDC_DAI = <IERC20>(
        await ethers.getContractAt("@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20", STABLE_USDC_DAI.poolAddress)
      );

      await getAccountToken(units(10000), logicOwner.address, assets.usdc, assetsBalanceOfSlot.usdc);
      await getAccountToken(units(10000), logicOwner.address, assets.dai, assetsBalanceOfSlot.dai);

      const funds = await createFund(poolFactory, logicOwner, manager, [
        { asset: assets.usdc, isDeposit: true },
        { asset: STABLE_USDC_DAI.poolAddress, isDeposit: false },
        { asset: assets.dai, isDeposit: true },
      ]);
      poolLogicProxy = funds.poolLogicProxy;

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

      approveABI = iERC20.encodeFunctionData("approve", [STABLE_USDC_DAI.gaugeAddress, lpAmount]);
      await poolLogicProxy.connect(manager).execTransaction(STABLE_USDC_DAI.poolAddress, approveABI);
    });

    utils.beforeAfterReset(beforeEach, afterEach);

    describe("addLiquidity", () => {
      it("Reverts if tokenA is not supported asset", async () => {
        const addLiquidityTx = iVelodromeRouter.encodeFunctionData("addLiquidity", [
          assets.weth,
          assets.dai,
          STABLE_USDC_DAI.isStable,
          units(100, 6),
          units(100),
          0,
          0,
          poolLogicProxy.address,
          ethers.constants.MaxUint256,
        ]);
        await expect(poolLogicProxy.connect(manager).execTransaction(router, addLiquidityTx)).to.revertedWith(
          "unsupported asset: tokenA",
        );
      });

      it("Reverts if tokenB is not supported asset", async () => {
        const addLiquidityTx = iVelodromeRouter.encodeFunctionData("addLiquidity", [
          assets.usdc,
          assets.weth,
          STABLE_USDC_DAI.isStable,
          units(100, 6),
          units(100),
          0,
          0,
          poolLogicProxy.address,
          ethers.constants.MaxUint256,
        ]);
        await expect(poolLogicProxy.connect(manager).execTransaction(router, addLiquidityTx)).to.revertedWith(
          "unsupported asset: tokenB",
        );
      });

      it("Reverts if lp asset is not supported asset", async () => {
        const addLiquidityTx = iVelodromeRouter.encodeFunctionData("addLiquidity", [
          assets.usdc,
          assets.dai,
          VARIABLE_WETH_USDC.isStable,
          units(100, 6),
          units(100),
          0,
          0,
          poolLogicProxy.address,
          ethers.constants.MaxUint256,
        ]);
        await expect(poolLogicProxy.connect(manager).execTransaction(router, addLiquidityTx)).to.revertedWith(
          "unsupported lp asset",
        );
      });

      it("Reverts if recipient is not pool logic", async () => {
        const addLiquidityTx = iVelodromeRouter.encodeFunctionData("addLiquidity", [
          assets.usdc,
          assets.dai,
          STABLE_USDC_DAI.isStable,
          units(100, 6),
          units(100),
          0,
          0,
          userNotPool.address,
          ethers.constants.MaxUint256,
        ]);
        await expect(poolLogicProxy.connect(manager).execTransaction(router, addLiquidityTx)).to.revertedWith(
          "recipient is not pool",
        );
      });

      it("Allow add liquidity", async () => {
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

        const liquidityBefore = await VELODROME_USDC_DAI.balanceOf(poolLogicProxy.address);

        await poolLogicProxy.connect(manager).execTransaction(router, addLiquidityTx);

        const liquidityAfter = await VELODROME_USDC_DAI.balanceOf(poolLogicProxy.address);

        expect(liquidityAfter).to.gt(liquidityBefore);
      });
    });

    describe("removeLiquidity", () => {
      it("Reverts if tokenA is not supported asset", async () => {
        const removeLiquidityTx = iVelodromeRouter.encodeFunctionData("removeLiquidity", [
          assets.weth,
          assets.dai,
          STABLE_USDC_DAI.isStable,
          lpAmount,
          0,
          0,
          poolLogicProxy.address,
          ethers.constants.MaxUint256,
        ]);
        await expect(poolLogicProxy.connect(manager).execTransaction(router, removeLiquidityTx)).to.revertedWith(
          "unsupported asset: tokenA",
        );
      });

      it("Reverts if tokenB is not supported asset", async () => {
        const removeLiquidityTx = iVelodromeRouter.encodeFunctionData("removeLiquidity", [
          assets.usdc,
          assets.weth,
          STABLE_USDC_DAI.isStable,
          lpAmount,
          0,
          0,
          poolLogicProxy.address,
          ethers.constants.MaxUint256,
        ]);
        await expect(poolLogicProxy.connect(manager).execTransaction(router, removeLiquidityTx)).to.revertedWith(
          "unsupported asset: tokenB",
        );
      });

      it("Reverts if lp asset is not supported asset", async () => {
        const removeLiquidityTx = iVelodromeRouter.encodeFunctionData("removeLiquidity", [
          assets.usdc,
          assets.dai,
          VARIABLE_WETH_USDC.isStable,
          lpAmount,
          0,
          0,
          poolLogicProxy.address,
          ethers.constants.MaxUint256,
        ]);
        await expect(poolLogicProxy.connect(manager).execTransaction(router, removeLiquidityTx)).to.revertedWith(
          "unsupported lp asset",
        );
      });

      it("Reverts if recipient is not pool logic", async () => {
        const removeLiquidityTx = iVelodromeRouter.encodeFunctionData("removeLiquidity", [
          assets.usdc,
          assets.dai,
          STABLE_USDC_DAI.isStable,
          lpAmount,
          0,
          0,
          userNotPool.address,
          ethers.constants.MaxUint256,
        ]);
        await expect(poolLogicProxy.connect(manager).execTransaction(router, removeLiquidityTx)).to.revertedWith(
          "recipient is not pool",
        );
      });

      it("Allow remove liquidity", async () => {
        const approveABI = iERC20.encodeFunctionData("approve", [router, lpAmount]);
        await poolLogicProxy.connect(manager).execTransaction(VELODROME_USDC_DAI.address, approveABI);

        const removeLiquidityTx = iVelodromeRouter.encodeFunctionData("removeLiquidity", [
          assets.usdc,
          assets.dai,
          STABLE_USDC_DAI.isStable,
          lpAmount,
          0,
          0,
          poolLogicProxy.address,
          ethers.constants.MaxUint256,
        ]);

        const liquidityBefore = await VELODROME_USDC_DAI.balanceOf(poolLogicProxy.address);

        await poolLogicProxy.connect(manager).execTransaction(router, removeLiquidityTx);

        const liquidityAfter = await VELODROME_USDC_DAI.balanceOf(poolLogicProxy.address);

        expect(liquidityAfter).to.lt(liquidityBefore);
        expect(liquidityAfter).to.equal(0);
      });
    });
  });
};

[
  { ...velodrome, routerFactory: IVelodromeRouter__factory },
  { ...velodromeV2, routerFactory: IVelodromeV2Router__factory },
].forEach(runTests);
