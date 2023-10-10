import { ethers } from "hardhat";
import { expect } from "chai";
import { units } from "../../../testHelpers";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import {
  IArrakisV1RouterStaking__factory,
  IERC20,
  IERC20__factory,
  PoolFactory,
  PoolLogic,
  PoolManagerLogic,
} from "../../../../types";
import { createFund } from "../../utils/createFund";
import { getAccountToken } from "../../utils/getAccountTokens";
import { deployContracts, NETWORK } from "../../utils/deployContracts/deployContracts";
import { utils } from "../../utils/utils";
import { Address } from "../../../../deployment/types";
import { arrakisRewardsFinished, deployArrakis } from "./arrakisDeployHelper";
import { BigNumber } from "ethers";

export const ArrakisLiquidityGaugeV4AssetGuardTest = (
  network: NETWORK,
  arrakisData: {
    v1RouterStaking: Address;
    usdcWethGauge: Address;
  },
  rewardsTokenAddress: Address,
  assets: {
    usdc: Address;
    weth: Address;
  },
  assetsBalanceOfSlot: {
    usdc: number;
    weth: number;
  },
) => {
  describe("ArrakisLiquidityGaugeV4AssetGuard Test", function () {
    let USDC: IERC20, weth: IERC20, rewardsToken: IERC20;
    let logicOwner: SignerWithAddress, manager: SignerWithAddress;
    let poolFactory: PoolFactory, poolLogicProxy: PoolLogic, poolManagerLogicProxy: PoolManagerLogic;
    const iERC20 = new ethers.utils.Interface(IERC20__factory.abi);
    const iArrakisV1RouterStaking = new ethers.utils.Interface(IArrakisV1RouterStaking__factory.abi);

    let token0Amount: BigNumber;
    let token1Amount: BigNumber;

    utils.beforeAfterReset(before, after);
    utils.beforeAfterReset(beforeEach, afterEach);

    const usdcInvestmentAmount = units(1000, 6);
    const wethInvestmentAmount = units(1);
    before(async function () {
      [logicOwner, manager] = await ethers.getSigners();
      const deployments = await deployContracts(network);
      await deployArrakis(deployments, arrakisData);
      poolFactory = deployments.poolFactory;
      USDC = deployments.assets.USDC;
      weth = <IERC20>await ethers.getContractAt("@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20", assets.weth);
      rewardsToken = <IERC20>(
        await ethers.getContractAt("@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20", rewardsTokenAddress)
      );

      const gauge = await ethers.getContractAt("ILiquidityGaugeV4", arrakisData.usdcWethGauge);
      const stakingToken = await gauge.staking_token();

      const vault = await ethers.getContractAt("IArrakisVaultV1", stakingToken);

      token0Amount =
        (await vault.token0()).toLowerCase() == assets.usdc.toLowerCase() ? usdcInvestmentAmount : wethInvestmentAmount;
      token1Amount =
        (await vault.token1()).toLowerCase() == assets.usdc.toLowerCase() ? usdcInvestmentAmount : wethInvestmentAmount;

      await getAccountToken(usdcInvestmentAmount, logicOwner.address, assets.usdc, assetsBalanceOfSlot.usdc);
      await getAccountToken(wethInvestmentAmount, logicOwner.address, assets.weth, assetsBalanceOfSlot.weth);

      const funds = await createFund(
        poolFactory,
        logicOwner,
        manager,
        [
          { asset: assets.usdc, isDeposit: true },
          { asset: assets.weth, isDeposit: true },
          { asset: rewardsTokenAddress, isDeposit: false },
        ],
        {
          performance: ethers.BigNumber.from("0"),
          management: ethers.BigNumber.from("0"),
        },
      );
      poolLogicProxy = funds.poolLogicProxy;
      poolManagerLogicProxy = funds.poolManagerLogicProxy;
      await USDC.approve(poolLogicProxy.address, usdcInvestmentAmount);
      await poolLogicProxy.deposit(assets.usdc, usdcInvestmentAmount);
      await weth.approve(poolLogicProxy.address, wethInvestmentAmount);
      await poolLogicProxy.deposit(assets.weth, wethInvestmentAmount);

      await poolManagerLogicProxy
        .connect(manager)
        .changeAssets([{ asset: arrakisData.usdcWethGauge, isDeposit: false }], []);

      let approveABI = iERC20.encodeFunctionData("approve", [arrakisData.v1RouterStaking, usdcInvestmentAmount]);
      await poolLogicProxy.connect(manager).execTransaction(assets.usdc, approveABI);
      approveABI = iERC20.encodeFunctionData("approve", [arrakisData.v1RouterStaking, wethInvestmentAmount]);
      await poolLogicProxy.connect(manager).execTransaction(assets.weth, approveABI);
      await poolLogicProxy.connect(manager).execTransaction(rewardsTokenAddress, approveABI);
    });

    it("stake should work: USDC-weth", async () => {
      // stake & asset guard should work
      const addLiquidityAndStakeABI = iArrakisV1RouterStaking.encodeFunctionData("addLiquidityAndStake", [
        arrakisData.usdcWethGauge,
        token0Amount,
        token1Amount,
        units(0),
        units(0),
        units(0),
        poolLogicProxy.address,
      ]);

      const usdcBalanceBefore = await USDC.balanceOf(poolLogicProxy.address);
      const wethBalanceBefore = await weth.balanceOf(poolLogicProxy.address);
      const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

      await poolLogicProxy.connect(manager).execTransaction(arrakisData.v1RouterStaking, addLiquidityAndStakeABI);

      const usdcBalanceAfter = await USDC.balanceOf(poolLogicProxy.address);
      const wethBalanceAfter = await weth.balanceOf(poolLogicProxy.address);
      const totalFundValueAfter = await poolManagerLogicProxy.totalFundValue();

      // check balance/totalFundValue changes after deposit
      // USDC/weth balance should be decreased and the gauge asset pricing should work
      // assume the price has 0.1% of volatility (chainlink vs UniV3)
      expect(usdcBalanceAfter).to.be.lt(usdcBalanceBefore);
      expect(wethBalanceAfter).to.be.lt(wethBalanceBefore);
      expect(totalFundValueAfter).to.closeTo(totalFundValueBefore, totalFundValueBefore.div(1000));
    });

    it("remove liquidity and unstake should work", async () => {
      const usdcBalanceBefore = await USDC.balanceOf(poolLogicProxy.address);
      const wethBalanceBefore = await weth.balanceOf(poolLogicProxy.address);
      const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

      // stake & unstake
      const addLiquidityAndStakeABI = iArrakisV1RouterStaking.encodeFunctionData("addLiquidityAndStake", [
        arrakisData.usdcWethGauge,
        token0Amount,
        token1Amount,
        units(0),
        units(0),
        units(0),
        poolLogicProxy.address,
      ]);
      await poolLogicProxy.connect(manager).execTransaction(arrakisData.v1RouterStaking, addLiquidityAndStakeABI);

      const gauge = await ethers.getContractAt(
        "@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20",
        arrakisData.usdcWethGauge,
      );
      const burnAmount = await gauge.balanceOf(poolLogicProxy.address);

      const approveABI = iERC20.encodeFunctionData("approve", [arrakisData.v1RouterStaking, burnAmount]);
      await poolLogicProxy.connect(manager).execTransaction(arrakisData.usdcWethGauge, approveABI);

      const removeLiquidityAndUnstakeABI = iArrakisV1RouterStaking.encodeFunctionData("removeLiquidityAndUnstake", [
        arrakisData.usdcWethGauge,
        burnAmount,
        units(0),
        units(0),
        poolLogicProxy.address,
      ]);
      await poolLogicProxy.connect(manager).execTransaction(arrakisData.v1RouterStaking, removeLiquidityAndUnstakeABI);

      // check balance/totalFundValue changes after deposit & immediate withdraw
      // USDC/weth balance and totalFundValue should be nearly same
      // assume the price has 0.1% of volatility (chainlink vs UniV3)
      expect(await USDC.balanceOf(poolLogicProxy.address)).to.be.closeTo(
        usdcBalanceBefore,
        usdcBalanceBefore.div(1000),
      );
      expect(await weth.balanceOf(poolLogicProxy.address)).to.be.closeTo(
        wethBalanceBefore,
        wethBalanceBefore.div(1000),
      );
      expect(await poolManagerLogicProxy.totalFundValue()).to.closeTo(
        totalFundValueBefore,
        totalFundValueBefore.div(1000),
      );
    });

    it("withdraw should work", async function () {
      const gauge = await ethers.getContractAt("ILiquidityGaugeV4", arrakisData.usdcWethGauge);

      let approveABI = iERC20.encodeFunctionData("approve", [arrakisData.v1RouterStaking, usdcInvestmentAmount]);
      await poolLogicProxy.connect(manager).execTransaction(assets.usdc, approveABI);
      approveABI = iERC20.encodeFunctionData("approve", [arrakisData.v1RouterStaking, wethInvestmentAmount]);
      await poolLogicProxy.connect(manager).execTransaction(assets.weth, approveABI);

      const addLiquidityAndStakeABI = iArrakisV1RouterStaking.encodeFunctionData("addLiquidityAndStake", [
        arrakisData.usdcWethGauge,
        token0Amount,
        token1Amount,
        units(0),
        units(0),
        units(0),
        poolLogicProxy.address,
      ]);
      await poolManagerLogicProxy
        .connect(manager)
        .changeAssets([{ asset: arrakisData.usdcWethGauge, isDeposit: false }], []);
      await poolLogicProxy.connect(manager).execTransaction(arrakisData.v1RouterStaking, addLiquidityAndStakeABI);

      await ethers.provider.send("evm_increaseTime", [3600 * 24]);
      await ethers.provider.send("evm_mine", []);

      const usdcBalanceBefore = await USDC.balanceOf(poolLogicProxy.address);
      const wethBalanceBefore = await weth.balanceOf(poolLogicProxy.address);
      const rewardsTokenBalanceBefore = await rewardsToken.balanceOf(poolLogicProxy.address);
      const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

      const claimableRewards = await gauge.claimable_reward(poolLogicProxy.address, rewardsToken.address);

      // withdraw half
      await poolFactory.setExitCooldown(0);
      await poolManagerLogicProxy.connect(manager).changeAssets([{ asset: rewardsTokenAddress, isDeposit: false }], []);
      await poolLogicProxy.withdraw((await poolLogicProxy.balanceOf(logicOwner.address)).div(2));

      // Assert all the rewards are claimed
      expect(await gauge.claimable_reward(poolLogicProxy.address, rewardsToken.address)).to.equal(0);

      const usdcBalanceAfter = await USDC.balanceOf(poolLogicProxy.address);
      const wethBalanceAfter = await weth.balanceOf(poolLogicProxy.address);
      const rewardsTokenBalanceAfter = await rewardsToken.balanceOf(poolLogicProxy.address);

      // check users USDC/weth and rewardsToken balance changes after withdraw
      // should receive half of the pool value including the rewardsToken rewards
      // assume the price has 0.1% of volatility (chainlink vs UniV3)
      expect(await USDC.balanceOf(logicOwner.address)).to.closeTo(
        usdcInvestmentAmount.div(2),
        usdcInvestmentAmount.div(1000),
      );
      expect(await weth.balanceOf(logicOwner.address)).to.closeTo(
        wethInvestmentAmount.div(2),
        wethInvestmentAmount.div(1000),
      );

      if (!(await arrakisRewardsFinished(arrakisData.usdcWethGauge, rewardsTokenAddress))) {
        expect(await rewardsToken.balanceOf(logicOwner.address)).to.closeTo(
          rewardsTokenBalanceBefore.add(claimableRewards).div(2),
          rewardsTokenBalanceBefore.add(claimableRewards).div(2).div(1000),
        );

        expect(rewardsTokenBalanceAfter).to.closeTo(
          rewardsTokenBalanceBefore.add(claimableRewards).div(2),
          rewardsTokenBalanceBefore.add(claimableRewards).div(2).div(1000),
        );
      }

      // check pool USDC/weth balances after withdraw
      // should be half than before withdraw, but there can be 1 wei difference
      expect(usdcBalanceAfter).to.closeTo(usdcBalanceBefore.div(2), 1);
      expect(wethBalanceAfter).to.closeTo(wethBalanceBefore.div(2), 1);
      // check totalFundValue after withdraw
      // should be half than before withdraw
      // assume the price has 0.1% of volatility (chainlink vs UniV3)
      expect(await poolManagerLogicProxy.totalFundValue()).to.closeTo(
        totalFundValueBefore.div(2),
        totalFundValueBefore.div(2).div(1000),
      );
    });

    it("withdraw should work (without staking)", async () => {
      const usdcBalanceBefore = await USDC.balanceOf(poolLogicProxy.address);
      const wethBalanceBefore = await weth.balanceOf(poolLogicProxy.address);
      const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

      // withdraw half
      await ethers.provider.send("evm_increaseTime", [86400]);
      await poolLogicProxy.withdraw((await poolLogicProxy.balanceOf(logicOwner.address)).div(2));

      // check users USDC/weth balance changes after withdraw
      // should receive half of the pool value, but there can be 1 wei difference
      expect(await USDC.balanceOf(logicOwner.address)).to.closeTo(usdcBalanceBefore.div(2), 1);
      expect(await weth.balanceOf(logicOwner.address)).to.closeTo(wethBalanceBefore.div(2), 1);

      // check pool USDC/weth balances after withdraw
      // should be half than before withdraw, but there can be 1 wei difference
      expect(await USDC.balanceOf(poolLogicProxy.address)).to.closeTo(usdcBalanceBefore.div(2), 1);
      expect(await weth.balanceOf(poolLogicProxy.address)).to.closeTo(wethBalanceBefore.div(2), 1);
      // check totalFundValue after withdraw
      // should be half than before withdraw, but the balances can have 1 wei difference and usdc has 6 decimals
      expect(await poolManagerLogicProxy.totalFundValue()).to.closeTo(totalFundValueBefore.div(2), units(1, 12));
    });
  });
};
