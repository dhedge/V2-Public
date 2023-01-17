import { ethers } from "hardhat";
import { expect } from "chai";
import { checkAlmostSame, units } from "../../../TestHelpers";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import {
  IArrakisV1RouterStaking__factory,
  IERC20,
  IERC20__factory,
  ILiquidityGaugeV4__factory,
  PoolFactory,
  PoolLogic,
  PoolManagerLogic,
} from "../../../../types";
import { createFund } from "../../utils/createFund";
import { getAccountToken } from "../../utils/getAccountTokens";
import { deployContracts, NETWORK } from "../../utils/deployContracts/deployContracts";
import { utils } from "../../utils/utils";
import { Address } from "../../../../deployment-scripts/types";
import { arrakisRewardsFinished, deployArrakis } from "./arrakisDeployHelper";
import { BigNumber } from "ethers";

export const ArrakisLiquidityGaugeV4ContractGuardTest = (
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
  describe("ArrakisLiquidityGaugeV4ContractGuard Test", function () {
    const { usdcWethGauge, v1RouterStaking } = arrakisData;
    let USDC: IERC20, weth: IERC20, rewardsToken: IERC20;
    let logicOwner: SignerWithAddress, manager: SignerWithAddress;
    let poolFactory: PoolFactory, poolLogicProxy: PoolLogic, poolManagerLogicProxy: PoolManagerLogic;
    const iERC20 = new ethers.utils.Interface(IERC20__factory.abi);
    const iArrakisV1RouterStaking = new ethers.utils.Interface(IArrakisV1RouterStaking__factory.abi);
    const iLiquidityGaugeV4 = new ethers.utils.Interface(ILiquidityGaugeV4__factory.abi);
    const usdcInvestmentAmount = units(1000, 6);
    const wethInvestmentAmount = units(1);
    let token0Amount: BigNumber;
    let token1Amount: BigNumber;

    utils.beforeAfterReset(before, after);
    utils.beforeAfterReset(beforeEach, afterEach);

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
      await getAccountToken(usdcInvestmentAmount, logicOwner.address, assets.usdc, assetsBalanceOfSlot.usdc);
      await getAccountToken(wethInvestmentAmount, logicOwner.address, assets.weth, assetsBalanceOfSlot.weth);

      const gauge = await ethers.getContractAt("ILiquidityGaugeV4", usdcWethGauge);
      const stakingToken = await gauge.staking_token();

      const vault = await ethers.getContractAt("IArrakisVaultV1", stakingToken);

      token0Amount =
        (await vault.token0()).toLowerCase() == assets.usdc.toLowerCase() ? usdcInvestmentAmount : wethInvestmentAmount;
      token1Amount =
        (await vault.token1()).toLowerCase() == assets.usdc.toLowerCase() ? usdcInvestmentAmount : wethInvestmentAmount;

      const funds = await createFund(poolFactory, logicOwner, manager, [
        { asset: assets.usdc, isDeposit: true },
        { asset: assets.weth, isDeposit: true },
      ]);
      poolLogicProxy = funds.poolLogicProxy;
      poolManagerLogicProxy = funds.poolManagerLogicProxy;
      // Deposit 200 USDC
      await USDC.approve(poolLogicProxy.address, usdcInvestmentAmount);
      await poolLogicProxy.deposit(assets.usdc, usdcInvestmentAmount);
      // Deposit 200 weth
      await weth.approve(poolLogicProxy.address, wethInvestmentAmount);
      await poolLogicProxy.deposit(assets.weth, wethInvestmentAmount);

      let approveABI = iERC20.encodeFunctionData("approve", [v1RouterStaking, usdcInvestmentAmount]);
      await poolLogicProxy.connect(manager).execTransaction(assets.usdc, approveABI);
      approveABI = iERC20.encodeFunctionData("approve", [v1RouterStaking, wethInvestmentAmount]);
      await poolLogicProxy.connect(manager).execTransaction(assets.weth, approveABI);

      const addLiquidityAndStakeABI = iArrakisV1RouterStaking.encodeFunctionData("addLiquidityAndStake", [
        usdcWethGauge,
        token0Amount,
        token1Amount,
        units(0),
        units(0),
        poolLogicProxy.address,
      ]);
      await poolManagerLogicProxy.connect(manager).changeAssets([{ asset: usdcWethGauge, isDeposit: false }], []);
      await poolManagerLogicProxy.connect(manager).changeAssets([{ asset: rewardsTokenAddress, isDeposit: false }], []);
      await poolLogicProxy.connect(manager).execTransaction(v1RouterStaking, addLiquidityAndStakeABI);
      await poolManagerLogicProxy.connect(manager).changeAssets([], [rewardsTokenAddress]);

      await ethers.provider.send("evm_increaseTime", [3600 * 24]);
      await ethers.provider.send("evm_mine", []);
    });

    it("claim_rewards()", async function () {
      if (await arrakisRewardsFinished(arrakisData.usdcWethGauge, rewardsTokenAddress)) {
        console.log("rewardsToken reward run out, Skipping test.");
        this.skip();
      } else {
        const claimABI = iLiquidityGaugeV4.encodeFunctionData("claim_rewards()", []);
        await expect(poolLogicProxy.connect(manager).execTransaction(usdcWethGauge, claimABI)).to.revertedWith(
          "enable reward token",
        );
      }
    });

    it("claim_rewards(address) - user is not pool", async function () {
      // claim_rewards(address)
      const claimABI = iLiquidityGaugeV4.encodeFunctionData("claim_rewards(address)", [logicOwner.address]);
      await expect(poolLogicProxy.connect(manager).execTransaction(usdcWethGauge, claimABI)).to.revertedWith(
        "user is not pool",
      );
    });

    it("claim_rewards(address) - enable reward token", async function () {
      if (await arrakisRewardsFinished(arrakisData.usdcWethGauge, rewardsTokenAddress)) {
        console.log("rewardsToken reward run out, Skipping test.");
        this.skip();
      } else {
        const claimABI = iLiquidityGaugeV4.encodeFunctionData("claim_rewards(address)", [poolLogicProxy.address]);
        await expect(poolLogicProxy.connect(manager).execTransaction(usdcWethGauge, claimABI)).to.revertedWith(
          "enable reward token",
        );
      }
    });

    it("claim_rewards(address,address)", async function () {
      let claimABI = iLiquidityGaugeV4.encodeFunctionData("claim_rewards(address,address)", [
        logicOwner.address,
        logicOwner.address,
      ]);
      await expect(poolLogicProxy.connect(manager).execTransaction(usdcWethGauge, claimABI)).to.revertedWith(
        "user is not pool",
      );
      claimABI = iLiquidityGaugeV4.encodeFunctionData("claim_rewards(address,address)", [
        poolLogicProxy.address,
        logicOwner.address,
      ]);
      await expect(poolLogicProxy.connect(manager).execTransaction(usdcWethGauge, claimABI)).to.revertedWith(
        "receiver is not pool",
      );
    });

    it("claim_rewards(address,address) - enable reward token", async function () {
      if (await arrakisRewardsFinished(arrakisData.usdcWethGauge, rewardsTokenAddress)) {
        console.log("rewardsToken reward run out, Skipping test.");
        this.skip();
      } else {
        const claimABI = iLiquidityGaugeV4.encodeFunctionData("claim_rewards(address,address)", [
          poolLogicProxy.address,
          poolLogicProxy.address,
        ]);
        await expect(poolLogicProxy.connect(manager).execTransaction(usdcWethGauge, claimABI)).to.revertedWith(
          "enable reward token",
        );
      }
    });

    it("claim should work", async function () {
      const usdcBalanceBefore = await USDC.balanceOf(poolLogicProxy.address);
      const wethBalanceBefore = await weth.balanceOf(poolLogicProxy.address);
      const rewardsTokenBalanceBefore = await rewardsToken.balanceOf(poolLogicProxy.address);
      const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

      if (await arrakisRewardsFinished(arrakisData.usdcWethGauge, rewardsTokenAddress)) {
        console.log("rewardsToken reward run out, Skipping test.");
        this.skip();
      } else {
        await poolManagerLogicProxy
          .connect(manager)
          .changeAssets([{ asset: rewardsTokenAddress, isDeposit: false }], []);
        const claimABI = iLiquidityGaugeV4.encodeFunctionData("claim_rewards(address,address)", [
          poolLogicProxy.address,
          poolLogicProxy.address,
        ]);
        await poolLogicProxy.connect(manager).execTransaction(usdcWethGauge, claimABI);

        expect(await USDC.balanceOf(poolLogicProxy.address)).to.be.eq(usdcBalanceBefore);
        expect(await weth.balanceOf(poolLogicProxy.address)).to.be.eq(wethBalanceBefore);
        expect(await rewardsToken.balanceOf(poolLogicProxy.address)).to.be.gt(rewardsTokenBalanceBefore);
        checkAlmostSame(await poolManagerLogicProxy.totalFundValue(), totalFundValueBefore, 0.05);
      }
    });
  });
};
