import { ethers } from "hardhat";
import { expect } from "chai";

import { IERC20, PoolFactory, PoolLogic, PoolManagerLogic } from "../../../../types";
import { IERC20Path } from "../../utils/deployContracts/deployBackboneContracts";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { ICompoundV3TestParams, iCompoundV3Comet, iCompoundV3CometRewards } from "./compoundV3TestDeploymentHelpers";
import { utils } from "../../utils/utils";
import { checkAlmostSame } from "../../../testHelpers";
import { setupCompoundV3ContractGuardTestBefore } from "./compoundV3ContractGuardTestHelpers";
import { deployEasySwapperV2 } from "../easySwapperV2/EasySwapperV2Test";
import { getEmptyComplexAssetsData } from "../aaveV3/deployAaveV3TestInfrastructure";

export const compoundV3CommonTest = (testParams: ICompoundV3TestParams) => {
  let { cAsset, baseAsset, baseAssetAmount, rewards } = testParams;
  let logicOwner: SignerWithAddress, manager: SignerWithAddress;
  let poolLogicProxy: PoolLogic, poolManagerLogicProxy: PoolManagerLogic;
  let poolFactory: PoolFactory;

  describe(`Compound v3 Comet Contract Guard Common Test ${testParams.assetName}`, function () {
    before(async function () {
      ({
        logicOwner,
        manager,
        poolLogicProxy,
        poolManagerLogicProxy,
        cAsset,
        baseAsset,
        baseAssetAmount,
        rewards,
        poolFactory,
      } = await setupCompoundV3ContractGuardTestBefore(testParams));
    });

    utils.beforeAfterReset(beforeEach, afterEach);

    describe("Supply to Compound", () => {
      it("Revert supply when asset invalid", async () => {
        const supplyTxData = iCompoundV3Comet.encodeFunctionData("supply", [cAsset, baseAssetAmount]);
        await expect(poolLogicProxy.connect(manager).execTransaction(cAsset, supplyTxData)).to.revertedWith(
          "invalid Compound asset",
        );
      });

      it("Revert supply when Compound asset not enabled", async () => {
        await poolManagerLogicProxy.connect(manager).changeAssets([], [cAsset]);

        const supplyTxData = iCompoundV3Comet.encodeFunctionData("supply", [baseAsset, baseAssetAmount]);
        await expect(poolLogicProxy.connect(manager).execTransaction(cAsset, supplyTxData)).to.revertedWith(
          "Compound not enabled",
        );
      });

      it("Can supply", async () => {
        const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();
        const baseAssetBalanceBefore = await poolManagerLogicProxy.assetBalance(baseAsset);
        const cAssetBalanceBefore = await poolManagerLogicProxy.assetBalance(cAsset);

        expect(baseAssetBalanceBefore).to.be.equal(baseAssetAmount);
        expect(cAssetBalanceBefore).to.be.equal(0);

        const supplyTxData = iCompoundV3Comet.encodeFunctionData("supply", [baseAsset, baseAssetAmount]);
        await poolLogicProxy.connect(manager).execTransaction(cAsset, supplyTxData);

        const baseAssetBalanceAfter = await poolManagerLogicProxy.assetBalance(baseAsset);
        const cAssetBalanceAfter = await poolManagerLogicProxy.assetBalance(cAsset);

        checkAlmostSame(await poolManagerLogicProxy.totalFundValue(), totalFundValueBefore, 0.00001);
        expect(baseAssetBalanceAfter).to.be.equal(0);
        expect(cAssetBalanceAfter).to.be.closeTo(baseAssetAmount, 2); // usually error of 1, but occasionally 2
      });
    });

    describe("Withdraw from Compound", () => {
      it("Revert withdraw when withdrawal asset set as another vault asset", async () => {
        const supplyTxData = iCompoundV3Comet.encodeFunctionData("supply", [baseAsset, baseAssetAmount]);
        await poolLogicProxy.connect(manager).execTransaction(cAsset, supplyTxData);

        const withdrawTxData = iCompoundV3Comet.encodeFunctionData("withdraw", [cAsset, baseAssetAmount.sub(1)]);

        await expect(poolLogicProxy.connect(manager).execTransaction(cAsset, withdrawTxData)).to.reverted; // handled by Compound contract
      });

      it("Revert withdraw when withdrawal asset invalid", async () => {
        const supplyTxData = iCompoundV3Comet.encodeFunctionData("supply", [baseAsset, baseAssetAmount]);
        await poolLogicProxy.connect(manager).execTransaction(cAsset, supplyTxData);

        const withdrawTxData = iCompoundV3Comet.encodeFunctionData("withdraw", [
          logicOwner.address, // invalid asset
          baseAssetAmount.sub(1),
        ]);

        await expect(poolLogicProxy.connect(manager).execTransaction(cAsset, withdrawTxData)).to.revertedWith(
          "unsupported withdrawal asset",
        );
      });

      it("Can withdraw", async () => {
        const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

        const supplyTxData = iCompoundV3Comet.encodeFunctionData("supply", [baseAsset, baseAssetAmount]);
        await poolLogicProxy.connect(manager).execTransaction(cAsset, supplyTxData);

        const cAssetBalanceBefore = await poolManagerLogicProxy.assetBalance(cAsset);

        const withdrawTxData = iCompoundV3Comet.encodeFunctionData("withdraw", [baseAsset, baseAssetAmount.sub(1)]);
        await poolLogicProxy.connect(manager).execTransaction(cAsset, withdrawTxData);

        const baseAssetBalanceAfter = await poolManagerLogicProxy.assetBalance(baseAsset);
        const cAssetBalanceAfter = await poolManagerLogicProxy.assetBalance(cAsset);

        checkAlmostSame(await poolManagerLogicProxy.totalFundValue(), totalFundValueBefore, 0.00001);
        expect(baseAssetBalanceAfter).to.be.closeTo(baseAssetAmount, 2);
        expect(cAssetBalanceAfter).to.be.lte(cAssetBalanceBefore.div(100_000)); // it looks like some dust can be left behind with 18 decimal markets
      });
    });

    describe("Withdraw from vault", () => {
      it("Can withdraw 50% from vault immediately", async () => {
        await ethers.provider.send("evm_increaseTime", [3600 * 24 * 1]); // 1 day to bypass token lockup

        const cAssetContract = <IERC20>await ethers.getContractAt(IERC20Path, cAsset);
        const baseAssetContract = <IERC20>await ethers.getContractAt(IERC20Path, baseAsset);

        const supplyTxData = iCompoundV3Comet.encodeFunctionData("supply", [baseAsset, baseAssetAmount]);
        await poolLogicProxy.connect(manager).execTransaction(cAsset, supplyTxData);

        const poolBalanceBefore = await poolLogicProxy.balanceOf(logicOwner.address);
        const baseAssetBalanceBefore = await baseAssetContract.balanceOf(logicOwner.address);
        const cAssetBalanceBefore = await cAssetContract.balanceOf(logicOwner.address);

        await poolLogicProxy.connect(logicOwner).withdraw(poolBalanceBefore.div(2));

        const poolBalanceAfter = await poolLogicProxy.balanceOf(logicOwner.address);
        const baseAssetBalanceAfter = await baseAssetContract.balanceOf(logicOwner.address);
        const cAssetBalanceAfter = await cAssetContract.balanceOf(logicOwner.address);

        expect(poolBalanceBefore).to.be.gt(0);
        expect(poolBalanceAfter).to.be.closeTo(poolBalanceBefore.div(2), 1);
        expect(baseAssetBalanceBefore).to.be.equal(0);
        expect(baseAssetBalanceAfter).to.be.closeTo(baseAssetAmount.div(2), baseAssetAmount.div(100_000));
        expect(cAssetBalanceBefore).to.be.equal(0);
        expect(cAssetBalanceAfter).to.be.equal(0);
      });

      it("Can withdraw 100% from vault immediately", async () => {
        await ethers.provider.send("evm_increaseTime", [3600 * 24 * 1]); // 1 day to bypass token lockup

        const cAssetContract = <IERC20>await ethers.getContractAt(IERC20Path, cAsset);
        const baseAssetContract = <IERC20>await ethers.getContractAt(IERC20Path, baseAsset);

        const supplyTxData = iCompoundV3Comet.encodeFunctionData("supply", [baseAsset, baseAssetAmount]);
        await poolLogicProxy.connect(manager).execTransaction(cAsset, supplyTxData);

        const poolBalanceBefore = await poolLogicProxy.balanceOf(logicOwner.address);
        const baseAssetBalanceBefore = await baseAssetContract.balanceOf(logicOwner.address);
        const cAssetBalanceBefore = await cAssetContract.balanceOf(logicOwner.address);

        await poolLogicProxy.connect(logicOwner).withdraw(poolBalanceBefore);

        const poolBalanceAfter = await poolLogicProxy.balanceOf(logicOwner.address);
        const baseAssetBalanceAfter = await baseAssetContract.balanceOf(logicOwner.address);
        const cAssetBalanceAfter = await cAssetContract.balanceOf(logicOwner.address);

        expect(poolBalanceBefore).to.be.gt(0);
        expect(poolBalanceAfter).to.be.equal(0);
        expect(baseAssetBalanceBefore).to.be.equal(0);
        expect(baseAssetBalanceAfter).to.be.closeTo(baseAssetAmount, baseAssetAmount.div(100_000));
        expect(cAssetBalanceBefore).to.be.equal(0);
        expect(cAssetBalanceAfter).to.be.equal(0);
      });

      it("Can withdraw 100% from vault with interest", async () => {
        await ethers.provider.send("evm_increaseTime", [3600 * 24 * 1]); // 1 day to bypass token lockup

        const cAssetContract = <IERC20>await ethers.getContractAt(IERC20Path, cAsset);
        const baseAssetContract = <IERC20>await ethers.getContractAt(IERC20Path, baseAsset);

        const supplyTxData = iCompoundV3Comet.encodeFunctionData("supply", [baseAsset, baseAssetAmount]);
        await poolLogicProxy.connect(manager).execTransaction(cAsset, supplyTxData);

        await ethers.provider.send("evm_increaseTime", [3600 * 24 * 1]); // 1 day to accrue interest

        const poolBalanceBefore = await poolLogicProxy.balanceOf(logicOwner.address);
        const baseAssetBalanceBefore = await baseAssetContract.balanceOf(logicOwner.address);
        const cAssetBalanceBefore = await cAssetContract.balanceOf(logicOwner.address);

        await poolLogicProxy.connect(logicOwner).withdraw(poolBalanceBefore);

        const poolBalanceAfter = await poolLogicProxy.balanceOf(logicOwner.address);
        const baseAssetBalanceAfter = await baseAssetContract.balanceOf(logicOwner.address);
        const cAssetBalanceAfter = await cAssetContract.balanceOf(logicOwner.address);

        expect(poolBalanceBefore).to.be.gt(0);
        expect(poolBalanceAfter).to.be.equal(0);
        expect(baseAssetBalanceBefore).to.be.equal(0);
        expect(baseAssetBalanceAfter).to.be.gt(baseAssetAmount); // interest earned
        expect(cAssetBalanceBefore).to.be.equal(0);
        expect(cAssetBalanceAfter).to.be.equal(0);
      });

      it("Can withdraw 100% from vault immediately through EasySwapperV2", async () => {
        const easySwapperV2 = await deployEasySwapperV2(
          testParams.assets.weth,
          testParams.easySwapperV2.wrappedNativeToken,
          testParams.easySwapperV2.swapper,
        );
        await easySwapperV2.setdHedgePoolFactory(poolFactory.address);

        await ethers.provider.send("evm_increaseTime", [3600 * 24 * 1]); // 1 day to bypass token lockup

        const cAssetContract = <IERC20>await ethers.getContractAt(IERC20Path, cAsset);
        const baseAssetContract = <IERC20>await ethers.getContractAt(IERC20Path, baseAsset);

        const supplyTxData = iCompoundV3Comet.encodeFunctionData("supply", [baseAsset, baseAssetAmount]);
        await poolLogicProxy.connect(manager).execTransaction(cAsset, supplyTxData);

        const poolBalanceBefore = await poolLogicProxy.balanceOf(logicOwner.address);
        const baseAssetBalanceBefore = await baseAssetContract.balanceOf(logicOwner.address);
        const cAssetBalanceBefore = await cAssetContract.balanceOf(logicOwner.address);

        await poolLogicProxy.approve(easySwapperV2.address, poolBalanceBefore);
        await easySwapperV2.unrollAndClaim(
          poolLogicProxy.address,
          poolBalanceBefore,
          await getEmptyComplexAssetsData(poolLogicProxy),
        );

        const poolBalanceAfter = await poolLogicProxy.balanceOf(logicOwner.address);
        const baseAssetBalanceAfter = await baseAssetContract.balanceOf(logicOwner.address);
        const cAssetBalanceAfter = await cAssetContract.balanceOf(logicOwner.address);

        expect(poolBalanceBefore).to.be.gt(0);
        expect(poolBalanceAfter).to.be.equal(0);
        expect(baseAssetBalanceBefore).to.be.equal(0);
        expect(baseAssetBalanceAfter).to.be.closeTo(baseAssetAmount, baseAssetAmount.div(100_000));
        expect(cAssetBalanceBefore).to.be.equal(0);
        expect(cAssetBalanceAfter).to.be.equal(0);
      });
    });

    describe("Rewards", () => {
      it("Revert claim rewards when receiver invalid", async () => {
        const supplyTxData = iCompoundV3Comet.encodeFunctionData("supply", [baseAsset, baseAssetAmount]);
        await poolLogicProxy.connect(manager).execTransaction(cAsset, supplyTxData);

        await ethers.provider.send("evm_increaseTime", [3600 * 24 * 1]); // 1 day

        const claimRewardsTxData = iCompoundV3CometRewards.encodeFunctionData("claim", [cAsset, manager.address, true]);

        await expect(poolLogicProxy.connect(manager).execTransaction(rewards, claimRewardsTxData)).to.revertedWith(
          "invalid receiver",
        );
      });

      it("Revert claim rewards when cAsset set as another vault asset", async () => {
        const supplyTxData = iCompoundV3Comet.encodeFunctionData("supply", [baseAsset, baseAssetAmount]);
        await poolLogicProxy.connect(manager).execTransaction(cAsset, supplyTxData);

        await ethers.provider.send("evm_increaseTime", [3600 * 24 * 1]); // 1 day

        const claimRewardsTxData = iCompoundV3CometRewards.encodeFunctionData("claim", [
          baseAsset, // not set as cAsset
          poolLogicProxy.address,
          true,
        ]);

        await expect(poolLogicProxy.connect(manager).execTransaction(rewards, claimRewardsTxData)).to.reverted; // handled by Compound contract
      });

      it("Revert claim rewards when cAsset address unknown", async () => {
        const supplyTxData = iCompoundV3Comet.encodeFunctionData("supply", [baseAsset, baseAssetAmount]);
        await poolLogicProxy.connect(manager).execTransaction(cAsset, supplyTxData);

        await ethers.provider.send("evm_increaseTime", [3600 * 24 * 1]); // 1 day

        const claimRewardsTxData = iCompoundV3CometRewards.encodeFunctionData("claim", [
          logicOwner.address, // invalid address
          poolLogicProxy.address,
          true,
        ]);

        await expect(poolLogicProxy.connect(manager).execTransaction(rewards, claimRewardsTxData)).to.reverted; // revert handled by Compound reward contract
      });

      it("Allow claim rewards", async () => {
        const supplyTxData = iCompoundV3Comet.encodeFunctionData("supply", [baseAsset, baseAssetAmount]);
        await poolLogicProxy.connect(manager).execTransaction(cAsset, supplyTxData);

        await ethers.provider.send("evm_increaseTime", [3600 * 24 * 1]); // 1 day

        const claimRewardsTxData = iCompoundV3CometRewards.encodeFunctionData("claim", [
          cAsset,
          poolLogicProxy.address,
          true,
        ]);
        await poolLogicProxy.connect(manager).execTransaction(rewards, claimRewardsTxData);

        const cAssetContract = <IERC20>await ethers.getContractAt(IERC20Path, cAsset);
        const rewardTokenBalance = await cAssetContract.balanceOf(poolLogicProxy.address);

        expect(rewardTokenBalance).to.be.gt(0);
      });
    });
  });
};
