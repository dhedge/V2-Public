import { ethers } from "hardhat";
import { solidity } from "ethereum-waffle";
import { expect, use } from "chai";
import { checkAlmostSame, units } from "../../../TestHelpers";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import {
  IERC20,
  IERC20__factory,
  IVelodromeGauge,
  IVelodromeGauge__factory,
  IVelodromeRouter__factory,
  PoolFactory,
  PoolLogic,
  PoolManagerLogic,
} from "../../../../types";
import { createFund } from "../../utils/createFund";
import { ovmChainData } from "../../../../config/chainData/ovm-data";
const { assets, assetsBalanceOfSlot, velodrome } = ovmChainData;
import { getAccountToken } from "../../utils/getAccountTokens";
import { deployContracts } from "../../utils/deployContracts/deployContracts";
import { utils } from "../../utils/utils";

use(solidity);

describe("VelodromeLPAssetGuard Test", function () {
  let USDC: IERC20, DAI: IERC20, VELO: IERC20, VELODROME_USDC_DAI: IERC20, VELODROME_USDC_DAI_GAUGE: IVelodromeGauge;
  let logicOwner: SignerWithAddress, manager: SignerWithAddress;
  let poolFactory: PoolFactory, poolLogicProxy: PoolLogic, poolManagerLogicProxy: PoolManagerLogic;
  let lpAmount;
  const iERC20 = new ethers.utils.Interface(IERC20__factory.abi);
  const iVelodromeRouter = new ethers.utils.Interface(IVelodromeRouter__factory.abi);
  const iVelodromeGauge = new ethers.utils.Interface(IVelodromeGauge__factory.abi);

  before(async function () {
    [logicOwner, manager] = await ethers.getSigners();
    const deployments = await deployContracts("ovm");
    poolFactory = deployments.poolFactory;

    USDC = <IERC20>await ethers.getContractAt("@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20", assets.usdc);
    DAI = <IERC20>await ethers.getContractAt("@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20", assets.dai);
    VELO = <IERC20>await ethers.getContractAt("@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20", velodrome.velo);
    VELODROME_USDC_DAI = <IERC20>(
      await ethers.getContractAt(
        "@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20",
        velodrome.STABLE_USDC_DAI.poolAddress,
      )
    );
    VELODROME_USDC_DAI_GAUGE = await ethers.getContractAt("IVelodromeGauge", velodrome.STABLE_USDC_DAI.gaugeAddress);

    await getAccountToken(units(10000), logicOwner.address, assets.usdc, assetsBalanceOfSlot.usdc);
    await getAccountToken(units(10000), logicOwner.address, assets.dai, assetsBalanceOfSlot.dai);

    const funds = await createFund(poolFactory, logicOwner, manager, [
      { asset: assets.usdc, isDeposit: true },
      { asset: assets.dai, isDeposit: true },
      { asset: velodrome.STABLE_USDC_DAI.poolAddress, isDeposit: false },
    ]);
    poolLogicProxy = funds.poolLogicProxy;
    poolManagerLogicProxy = funds.poolManagerLogicProxy;

    // Deposit 200 USDC
    await USDC.approve(poolLogicProxy.address, units(200, 6));
    await poolLogicProxy.deposit(assets.usdc, units(200, 6));
    // Deposit 200 DAI
    await DAI.approve(poolLogicProxy.address, units(200));
    await poolLogicProxy.deposit(assets.dai, units(200));

    let approveABI = iERC20.encodeFunctionData("approve", [velodrome.router, units(200, 6)]);
    await poolLogicProxy.connect(manager).execTransaction(assets.usdc, approveABI);
    approveABI = iERC20.encodeFunctionData("approve", [velodrome.router, units(200)]);
    await poolLogicProxy.connect(manager).execTransaction(assets.dai, approveABI);
  });

  let snapId: string;
  beforeEach(async () => {
    snapId = await utils.evmTakeSnap();
  });

  afterEach(async () => {
    await utils.evmRestoreSnap(snapId);
  });

  describe("withdrawProcessing", () => {
    beforeEach(async () => {
      const addLiquidityTx = iVelodromeRouter.encodeFunctionData("addLiquidity", [
        assets.usdc,
        assets.dai,
        velodrome.STABLE_USDC_DAI.isStable,
        units(100, 6),
        units(100),
        0,
        0,
        poolLogicProxy.address,
        ethers.constants.MaxUint256,
      ]);
      await poolLogicProxy.connect(manager).execTransaction(velodrome.router, addLiquidityTx);

      lpAmount = await VELODROME_USDC_DAI.balanceOf(poolLogicProxy.address);

      const approveABI = iERC20.encodeFunctionData("approve", [velodrome.STABLE_USDC_DAI.gaugeAddress, lpAmount]);
      await poolLogicProxy.connect(manager).execTransaction(velodrome.STABLE_USDC_DAI.poolAddress, approveABI);

      const depositABI = iVelodromeGauge.encodeFunctionData("deposit", [lpAmount, 0]);
      await poolLogicProxy.connect(manager).execTransaction(velodrome.STABLE_USDC_DAI.gaugeAddress, depositABI);

      await poolFactory.setExitCooldown(0);
      await ethers.provider.send("evm_increaseTime", [3600 * 24 * 3]); // 3 days
      await ethers.provider.send("evm_mine", []);
    });

    it("Pool has expected funds after withdraw", async () => {
      const usdcBalanceBefore = await USDC.balanceOf(poolLogicProxy.address);
      const daiBalanceBefore = await DAI.balanceOf(poolLogicProxy.address);
      const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();
      const gaugeBalanceBefore = await VELODROME_USDC_DAI_GAUGE.balanceOf(poolLogicProxy.address);

      console.log(gaugeBalanceBefore.toString());
      // withdraw half
      await poolLogicProxy.withdraw((await poolLogicProxy.balanceOf(logicOwner.address)).div(2));

      console.log(gaugeBalanceBefore.toString());
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
      const claimAmount = await VELODROME_USDC_DAI_GAUGE.earned(VELO.address, poolLogicProxy.address);
      expect(claimAmount).to.gt(0);

      // withdraw half
      await poolLogicProxy.withdraw((await poolLogicProxy.balanceOf(logicOwner.address)).div(2));

      checkAlmostSame(await VELO.balanceOf(poolLogicProxy.address), claimAmount.div(2), 0.05);
    });

    it("Withdrawer receives their portion of LP Tokens and Rewards", async () => {
      const claimAmount = await VELODROME_USDC_DAI_GAUGE.earned(VELO.address, poolLogicProxy.address);
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
        velodrome.STABLE_USDC_DAI.isStable,
        units(100, 6),
        units(100),
        0,
        0,
        poolLogicProxy.address,
        ethers.constants.MaxUint256,
      ]);
      await poolLogicProxy.connect(manager).execTransaction(velodrome.router, addLiquidityTx);

      // price change between chainlink & amm, threshold
      checkAlmostSame(await poolManagerLogicProxy.totalFundValue(), totalFundValueBefore, 0.05);

      lpAmount = await VELODROME_USDC_DAI.balanceOf(poolLogicProxy.address);

      totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();
      const usdcBalanceBefore = await USDC.balanceOf(poolLogicProxy.address);
      const daiBalanceBefore = await DAI.balanceOf(poolLogicProxy.address);

      const approveABI = iERC20.encodeFunctionData("approve", [velodrome.STABLE_USDC_DAI.gaugeAddress, lpAmount]);
      await poolLogicProxy.connect(manager).execTransaction(velodrome.STABLE_USDC_DAI.poolAddress, approveABI);

      const depositABI = iVelodromeGauge.encodeFunctionData("deposit", [lpAmount.div(2), 0]);
      await poolLogicProxy.connect(manager).execTransaction(velodrome.STABLE_USDC_DAI.gaugeAddress, depositABI);

      expect(await VELODROME_USDC_DAI.balanceOf(poolLogicProxy.address)).to.be.closeTo(lpAmount.div(2), 1);
      expect(await USDC.balanceOf(poolLogicProxy.address)).to.be.eq(usdcBalanceBefore);
      expect(await DAI.balanceOf(poolLogicProxy.address)).to.be.eq(daiBalanceBefore);
      expect(await poolManagerLogicProxy.totalFundValue()).to.equal(totalFundValueBefore);
    });

    it("Includes unclaimed rewards in Price", async () => {
      const addLiquidityTx = iVelodromeRouter.encodeFunctionData("addLiquidity", [
        assets.usdc,
        assets.dai,
        velodrome.STABLE_USDC_DAI.isStable,
        units(100, 6),
        units(100),
        0,
        0,
        poolLogicProxy.address,
        ethers.constants.MaxUint256,
      ]);
      await poolLogicProxy.connect(manager).execTransaction(velodrome.router, addLiquidityTx);

      lpAmount = await VELODROME_USDC_DAI.balanceOf(poolLogicProxy.address);

      const approveABI = iERC20.encodeFunctionData("approve", [velodrome.STABLE_USDC_DAI.gaugeAddress, lpAmount]);
      await poolLogicProxy.connect(manager).execTransaction(velodrome.STABLE_USDC_DAI.poolAddress, approveABI);

      const depositABI = iVelodromeGauge.encodeFunctionData("deposit", [lpAmount, 0]);
      await poolLogicProxy.connect(manager).execTransaction(velodrome.STABLE_USDC_DAI.gaugeAddress, depositABI);

      const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

      await ethers.provider.send("evm_increaseTime", [3600 * 24]);
      await ethers.provider.send("evm_mine", []);

      const claimAmount = await VELODROME_USDC_DAI_GAUGE.earned(VELO.address, poolLogicProxy.address);
      expect(claimAmount).to.gt(0);
      expect(await poolManagerLogicProxy.totalFundValue()).to.closeTo(
        totalFundValueBefore.add(await poolManagerLogicProxy["assetValue(address,uint256)"](VELO.address, claimAmount)),
        await poolManagerLogicProxy["assetValue(address,uint256)"](VELO.address, claimAmount.div(1000)),
      );
    });
  });
});
