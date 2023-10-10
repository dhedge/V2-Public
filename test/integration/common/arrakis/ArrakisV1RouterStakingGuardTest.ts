import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { ethers } from "hardhat";
import {
  IArrakisV1RouterStaking__factory,
  IERC20,
  IERC20__factory,
  PoolFactory,
  PoolLogic,
  PoolManagerLogic,
} from "../../../../types";
import { checkAlmostSame, units } from "../../../testHelpers";
import { createFund } from "../../utils/createFund";
import { deployContracts, NETWORK } from "../../utils/deployContracts/deployContracts";
import { getAccountToken } from "../../utils/getAccountTokens";
import { utils } from "../../utils/utils";

import { Address } from "../../../../deployment/types";
import { arrakisRewardsFinished, deployArrakis } from "./arrakisDeployHelper";
import { BigNumber } from "ethers";

export const ArrakisV1RouterStakingGuardTest = (
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
  describe("ArrakisV1RouterStakingGuard Test", function () {
    const { usdcWethGauge, v1RouterStaking } = arrakisData;
    let USDC: IERC20, weth: IERC20;
    let logicOwner: SignerWithAddress, manager: SignerWithAddress;
    let poolFactory: PoolFactory, poolLogicProxy: PoolLogic, poolManagerLogicProxy: PoolManagerLogic;
    const iERC20 = new ethers.utils.Interface(IERC20__factory.abi);
    const iArrakisV1RouterStaking = new ethers.utils.Interface(IArrakisV1RouterStaking__factory.abi);

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

      await getAccountToken(usdcInvestmentAmount, logicOwner.address, assets.usdc, assetsBalanceOfSlot.usdc);
      await getAccountToken(wethInvestmentAmount, logicOwner.address, assets.weth, assetsBalanceOfSlot.weth);

      const funds = await createFund(poolFactory, logicOwner, manager, [
        { asset: assets.usdc, isDeposit: true },
        { asset: assets.weth, isDeposit: true },
      ]);
      poolLogicProxy = funds.poolLogicProxy;
      poolManagerLogicProxy = funds.poolManagerLogicProxy;

      const gauge = await ethers.getContractAt("ILiquidityGaugeV4", usdcWethGauge);
      const stakingToken = await gauge.staking_token();

      const vault = await ethers.getContractAt("IArrakisVaultV1", stakingToken);

      token0Amount =
        (await vault.token0()).toLowerCase() == assets.usdc.toLowerCase() ? usdcInvestmentAmount : wethInvestmentAmount;
      token1Amount =
        (await vault.token1()).toLowerCase() == assets.usdc.toLowerCase() ? usdcInvestmentAmount : wethInvestmentAmount;

      // Deposit 200 USDC
      await USDC.approve(poolLogicProxy.address, usdcInvestmentAmount);
      await poolLogicProxy.deposit(assets.usdc, usdcInvestmentAmount);
      // Deposit 200 weth
      await weth.approve(poolLogicProxy.address, wethInvestmentAmount);
      await poolLogicProxy.deposit(assets.weth, wethInvestmentAmount);
    });

    let snapId: string;
    beforeEach(async () => {
      snapId = await utils.evmTakeSnap();
    });

    afterEach(async () => {
      await utils.evmRestoreSnap(snapId);
    });

    describe("Add liquidity and stake", () => {
      beforeEach(async () => {
        let approveABI = iERC20.encodeFunctionData("approve", [v1RouterStaking, usdcInvestmentAmount]);
        await poolLogicProxy.connect(manager).execTransaction(assets.usdc, approveABI);
        approveABI = iERC20.encodeFunctionData("approve", [v1RouterStaking, wethInvestmentAmount]);
        await poolLogicProxy.connect(manager).execTransaction(assets.weth, approveABI);
      });

      it("unsupported gauge token", async () => {
        const addLiquidityAndStakeABI = iArrakisV1RouterStaking.encodeFunctionData("addLiquidityAndStake", [
          // hasnt been added to pool as an asset
          arrakisData.usdcWethGauge,
          token0Amount,
          token1Amount,
          units(0),
          units(0),
          units(0),
          poolLogicProxy.address,
        ]);
        await expect(
          poolLogicProxy.connect(manager).execTransaction(v1RouterStaking, addLiquidityAndStakeABI),
        ).to.revertedWith("unsupported gauge token");
      });

      it("unsupported asset: token1Amount", async () => {
        const addLiquidityAndStakeABI = iArrakisV1RouterStaking.encodeFunctionData("addLiquidityAndStake", [
          usdcWethGauge,
          token0Amount,
          token1Amount,
          units(0),
          units(0),
          units(0),
          poolLogicProxy.address,
        ]);
        await getAccountToken(BigNumber.from(0), poolLogicProxy.address, assets.usdc, assetsBalanceOfSlot.usdc);
        await poolManagerLogicProxy
          .connect(manager)
          .changeAssets([{ asset: usdcWethGauge, isDeposit: false }], [assets.usdc]);
        await expect(
          poolLogicProxy.connect(manager).execTransaction(v1RouterStaking, addLiquidityAndStakeABI),
        ).to.revertedWith("unsupported asset: token");
      });

      it("unsupported asset: token0", async () => {
        const addLiquidityAndStakeABI = iArrakisV1RouterStaking.encodeFunctionData("addLiquidityAndStake", [
          usdcWethGauge,
          token0Amount,
          token1Amount,
          units(0),
          units(0),
          units(0),
          poolLogicProxy.address,
        ]);
        await getAccountToken(BigNumber.from(0), poolLogicProxy.address, assets.weth, assetsBalanceOfSlot.weth);
        await poolManagerLogicProxy
          .connect(manager)
          .changeAssets([{ asset: usdcWethGauge, isDeposit: false }], [assets.weth]);
        await expect(
          poolLogicProxy.connect(manager).execTransaction(v1RouterStaking, addLiquidityAndStakeABI),
        ).to.revertedWith("unsupported asset: token");
      });

      it("receiver is not pool", async () => {
        await poolManagerLogicProxy.connect(manager).changeAssets(
          [
            { asset: rewardsTokenAddress, isDeposit: false },
            { asset: usdcWethGauge, isDeposit: false },
          ],
          [],
        );
        const addLiquidityAndStakeABI = iArrakisV1RouterStaking.encodeFunctionData("addLiquidityAndStake", [
          usdcWethGauge,
          token0Amount,
          token1Amount,
          units(0),
          units(0),
          units(0),
          logicOwner.address,
        ]);
        await expect(
          poolLogicProxy.connect(manager).execTransaction(v1RouterStaking, addLiquidityAndStakeABI),
        ).to.revertedWith("receiver is not pool");
      });

      it("reward token must be enabled", async () => {
        await poolManagerLogicProxy.connect(manager).changeAssets([{ asset: usdcWethGauge, isDeposit: false }], []);
        const addLiquidityAndStakeABI = iArrakisV1RouterStaking.encodeFunctionData("addLiquidityAndStake", [
          usdcWethGauge,
          token0Amount,
          token1Amount,
          units(0),
          units(0),
          units(0),
          logicOwner.address,
        ]);
        await expect(
          poolLogicProxy.connect(manager).execTransaction(v1RouterStaking, addLiquidityAndStakeABI),
        ).to.revertedWith("enable reward token");
      });

      it("stake should work", async () => {
        await poolManagerLogicProxy.connect(manager).changeAssets(
          [
            { asset: usdcWethGauge, isDeposit: false },
            { asset: rewardsTokenAddress, isDeposit: false },
          ],
          [],
        );

        // stake & asset guard should work
        const addLiquidityAndStakeABI = iArrakisV1RouterStaking.encodeFunctionData("addLiquidityAndStake", [
          usdcWethGauge,
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

        await poolLogicProxy.connect(manager).execTransaction(v1RouterStaking, addLiquidityAndStakeABI);

        expect(await USDC.balanceOf(poolLogicProxy.address)).to.be.lt(usdcBalanceBefore);
        expect(await weth.balanceOf(poolLogicProxy.address)).to.be.lt(wethBalanceBefore);
        checkAlmostSame(await poolManagerLogicProxy.totalFundValue(), totalFundValueBefore, 0.05);
      });
    });

    describe("remove liquidity and unstake", () => {
      it("unsupported gauge token", async () => {
        const removeLiquidityAndUnstakeABI = iArrakisV1RouterStaking.encodeFunctionData("removeLiquidityAndUnstake", [
          // hasnt been added to pool as an asset
          arrakisData.usdcWethGauge,
          wethInvestmentAmount,
          units(0),
          units(0),
          poolLogicProxy.address,
        ]);
        await expect(
          poolLogicProxy.connect(manager).execTransaction(v1RouterStaking, removeLiquidityAndUnstakeABI),
        ).to.revertedWith("unsupported gauge token");
      });

      it("unsupported asset: token1Amount", async () => {
        const removeLiquidityAndUnstakeABI = iArrakisV1RouterStaking.encodeFunctionData("removeLiquidityAndUnstake", [
          usdcWethGauge,
          wethInvestmentAmount,
          units(0),
          units(0),
          poolLogicProxy.address,
        ]);
        await getAccountToken(BigNumber.from(0), poolLogicProxy.address, assets.usdc, assetsBalanceOfSlot.usdc);
        await poolManagerLogicProxy
          .connect(manager)
          .changeAssets([{ asset: usdcWethGauge, isDeposit: false }], [assets.usdc]);
        await expect(
          poolLogicProxy.connect(manager).execTransaction(v1RouterStaking, removeLiquidityAndUnstakeABI),
        ).to.revertedWith("unsupported asset: token");
      });

      it("unsupported asset: token0", async () => {
        const removeLiquidityAndUnstakeABI = iArrakisV1RouterStaking.encodeFunctionData("removeLiquidityAndUnstake", [
          usdcWethGauge,
          wethInvestmentAmount,
          units(0),
          units(0),
          poolLogicProxy.address,
        ]);
        await getAccountToken(BigNumber.from(0), poolLogicProxy.address, assets.weth, assetsBalanceOfSlot.weth);
        await poolManagerLogicProxy
          .connect(manager)
          .changeAssets([{ asset: usdcWethGauge, isDeposit: false }], [assets.weth]);
        await expect(
          poolLogicProxy.connect(manager).execTransaction(v1RouterStaking, removeLiquidityAndUnstakeABI),
        ).to.revertedWith("unsupported asset: token");
      });

      it("receiver is not pool", async () => {
        await poolManagerLogicProxy.connect(manager).changeAssets(
          [
            { asset: rewardsTokenAddress, isDeposit: false },
            { asset: usdcWethGauge, isDeposit: false },
          ],
          [],
        );
        const removeLiquidityAndUnstakeABI = iArrakisV1RouterStaking.encodeFunctionData("removeLiquidityAndUnstake", [
          usdcWethGauge,
          wethInvestmentAmount,
          units(0),
          units(0),
          logicOwner.address,
        ]);
        await expect(
          poolLogicProxy.connect(manager).execTransaction(v1RouterStaking, removeLiquidityAndUnstakeABI),
        ).to.revertedWith("receiver is not pool");
      });

      it("reward token must be enabled", async function () {
        if (await arrakisRewardsFinished(arrakisData.usdcWethGauge, rewardsTokenAddress)) {
          console.log("rewardsToken reward run out, Skipping test.");
          this.skip();
        } else {
          await poolManagerLogicProxy.connect(manager).changeAssets(
            [
              { asset: rewardsTokenAddress, isDeposit: false },
              { asset: usdcWethGauge, isDeposit: false },
            ],
            [],
          );

          // stake & unstake
          let approveABI = iERC20.encodeFunctionData("approve", [v1RouterStaking, usdcInvestmentAmount]);
          await poolLogicProxy.connect(manager).execTransaction(assets.usdc, approveABI);
          approveABI = iERC20.encodeFunctionData("approve", [v1RouterStaking, wethInvestmentAmount]);
          await poolLogicProxy.connect(manager).execTransaction(assets.weth, approveABI);

          const addLiquidityAndStakeABI = iArrakisV1RouterStaking.encodeFunctionData("addLiquidityAndStake", [
            usdcWethGauge,
            wethInvestmentAmount,
            usdcInvestmentAmount,
            units(0),
            units(0),
            units(0),
            poolLogicProxy.address,
          ]);
          await poolLogicProxy.connect(manager).execTransaction(v1RouterStaking, addLiquidityAndStakeABI);

          await poolManagerLogicProxy.connect(manager).changeAssets([], [rewardsTokenAddress]);

          const gaugeToken = await ethers.getContractAt(
            "@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20",
            usdcWethGauge,
          );
          const burnAmount = (await gaugeToken.balanceOf(poolLogicProxy.address)).div(2);

          approveABI = iERC20.encodeFunctionData("approve", [v1RouterStaking, burnAmount]);
          await poolLogicProxy.connect(manager).execTransaction(usdcWethGauge, approveABI);

          const removeLiquidityAndUnstakeABI = iArrakisV1RouterStaking.encodeFunctionData("removeLiquidityAndUnstake", [
            usdcWethGauge,
            burnAmount,
            units(0),
            units(0),
            poolLogicProxy.address,
          ]);
          await expect(
            poolLogicProxy.connect(manager).execTransaction(v1RouterStaking, removeLiquidityAndUnstakeABI),
          ).to.revertedWith("enable reward token");
        }
      });

      it("stake & unstake should work", async () => {
        await poolManagerLogicProxy.connect(manager).changeAssets(
          [
            { asset: rewardsTokenAddress, isDeposit: false },
            { asset: usdcWethGauge, isDeposit: false },
          ],
          [],
        );

        // stake & unstake
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
          units(0),
          poolLogicProxy.address,
        ]);
        await poolLogicProxy.connect(manager).execTransaction(v1RouterStaking, addLiquidityAndStakeABI);

        const usdcBalanceBefore = await USDC.balanceOf(poolLogicProxy.address);
        const wethBalanceBefore = await weth.balanceOf(poolLogicProxy.address);

        const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

        const gauge = await ethers.getContractAt(
          "@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20",
          usdcWethGauge,
        );

        const burnAmount = (await gauge.balanceOf(poolLogicProxy.address)).div(2);

        approveABI = iERC20.encodeFunctionData("approve", [v1RouterStaking, burnAmount]);
        await poolLogicProxy.connect(manager).execTransaction(usdcWethGauge, approveABI);

        const removeLiquidityAndUnstakeABI = iArrakisV1RouterStaking.encodeFunctionData("removeLiquidityAndUnstake", [
          usdcWethGauge,
          burnAmount,
          units(0),
          units(0),
          poolLogicProxy.address,
        ]);
        await poolLogicProxy.connect(manager).execTransaction(v1RouterStaking, removeLiquidityAndUnstakeABI);

        expect(await USDC.balanceOf(poolLogicProxy.address)).to.be.gt(usdcBalanceBefore);
        expect(await weth.balanceOf(poolLogicProxy.address)).to.be.gt(wethBalanceBefore);
        checkAlmostSame(await poolManagerLogicProxy.totalFundValue(), totalFundValueBefore, 0.05);
      });
    });
  });
};
