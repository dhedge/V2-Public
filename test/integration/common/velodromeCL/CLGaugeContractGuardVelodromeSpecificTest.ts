import { ethers } from "hardhat";
import { expect } from "chai";
import { BigNumber } from "ethers";

import { IERC20, IVelodromeNonfungiblePositionManager, PoolLogic, PoolManagerLogic } from "../../../../types";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { IVelodromeCLTestParams, iERC20, iVelodromeCLGauge } from "./velodromeCLTestDeploymentHelpers";
import { utils } from "../../utils/utils";
import { checkAlmostSame } from "../../../testHelpers";
import { setupGaugeContractGuardTestBefore } from "./CLGaugeContractGuardTestHelpers";

const deadLine = Math.floor(Date.now() / 1000 + 100000000);

export const clGaugeContractGuardVelodromeSpecificTest = (testParams: IVelodromeCLTestParams) => {
  const { pairs } = testParams;
  const { bothSupportedPair } = pairs;

  describe("Velodrome CL Gauge Guard Specific Test", function () {
    let manager: SignerWithAddress;
    let poolLogicProxy: PoolLogic, poolManagerLogicProxy: PoolManagerLogic;
    let tokenId: BigNumber;
    let nonfungiblePositionManager: IVelodromeNonfungiblePositionManager;
    let logicOwner: SignerWithAddress;
    let token0: IERC20;
    let token1: IERC20;

    before(async function () {
      ({
        manager,
        poolLogicProxy,
        poolManagerLogicProxy,
        tokenId,
        nonfungiblePositionManager,
        token0,
        token1,
        logicOwner,
      } = await setupGaugeContractGuardTestBefore(testParams));
    });

    utils.beforeAfterReset(beforeEach, afterEach);

    describe("decreaseStakedLiquidity and increaseStakedLiquidity(only for Velodrome)", () => {
      it("Allow increasing staked liquidity", async () => {
        const depositTx = iVelodromeCLGauge.encodeFunctionData("deposit(uint256)", [tokenId]);
        await poolLogicProxy.connect(manager).execTransaction(bothSupportedPair.gauge, depositTx);
        await ethers.provider.send("evm_increaseTime", [3600 * 24]);
        await ethers.provider.send("evm_mine", []);
        const positionBefore = await nonfungiblePositionManager.positions(tokenId);

        const increaseStakedLiquidityTx = iVelodromeCLGauge.encodeFunctionData("increaseStakedLiquidity", [
          tokenId,
          bothSupportedPair.amount0,
          bothSupportedPair.amount1,
          0,
          0,
          deadLine,
        ]);
        const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

        let approveABI = iERC20.encodeFunctionData("approve", [bothSupportedPair.gauge, bothSupportedPair.amount0]);
        await poolLogicProxy.connect(manager).execTransaction(bothSupportedPair.token0, approveABI);
        approveABI = iERC20.encodeFunctionData("approve", [bothSupportedPair.gauge, bothSupportedPair.amount1]);
        await poolLogicProxy.connect(manager).execTransaction(bothSupportedPair.token1, approveABI);
        await poolLogicProxy.connect(manager).execTransaction(bothSupportedPair.gauge, increaseStakedLiquidityTx);

        checkAlmostSame(await poolManagerLogicProxy.totalFundValue(), totalFundValueBefore, 0.0001);

        const positionAfter = await nonfungiblePositionManager.positions(tokenId);

        expect(positionBefore.liquidity).to.lt(positionAfter.liquidity);
      });

      it("Allow decreasing staked liquidity", async () => {
        const depositTx = iVelodromeCLGauge.encodeFunctionData("deposit(uint256)", [tokenId]);
        await poolLogicProxy.connect(manager).execTransaction(bothSupportedPair.gauge, depositTx);
        await ethers.provider.send("evm_increaseTime", [3600 * 24]);
        await ethers.provider.send("evm_mine", []);
        const positionBefore = await nonfungiblePositionManager.positions(tokenId);

        const decreaseStakedLiquidityTx = iVelodromeCLGauge.encodeFunctionData("decreaseStakedLiquidity", [
          tokenId,
          positionBefore.liquidity.div(2),
          0,
          0,
          deadLine,
        ]);
        const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

        await poolLogicProxy.connect(manager).execTransaction(bothSupportedPair.gauge, decreaseStakedLiquidityTx);

        checkAlmostSame(await poolManagerLogicProxy.totalFundValue(), totalFundValueBefore, 0.00001);

        const positionAfter = await nonfungiblePositionManager.positions(tokenId);

        checkAlmostSame(positionAfter.liquidity, positionBefore.liquidity.div(2), 0.000001);
      });
    });

    describe("withdrawal from pool", () => {
      beforeEach(async () => {
        const depositTx = iVelodromeCLGauge.encodeFunctionData("deposit(uint256)", [tokenId]);
        await poolLogicProxy.connect(manager).execTransaction(bothSupportedPair.gauge, depositTx);
        // increase time by 1 day
        await ethers.provider.send("evm_increaseTime", [3600 * 24]);
        await ethers.provider.send("evm_mine", []);
      });
      it("Should be able to withdraw (after decreaseStakedLiquidity)", async () => {
        const sharesBefore = await poolLogicProxy.balanceOf(logicOwner.address);
        const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();
        const token0BalanceBefore = await token0.balanceOf(logicOwner.address);
        const token1BalanceBefore = await token1.balanceOf(logicOwner.address);
        // First decrease half the liquidity and move it to the fees to ensure both liquidity and fees get withdrawn correctly
        const positionBefore = await nonfungiblePositionManager.positions(tokenId);

        // decrease LP position by 50%
        const decreaseStakedLiquidityTx = iVelodromeCLGauge.encodeFunctionData("decreaseStakedLiquidity", [
          tokenId,
          positionBefore.liquidity.div(2),
          0,
          0,
          deadLine,
        ]);
        await poolLogicProxy.connect(manager).execTransaction(bothSupportedPair.gauge, decreaseStakedLiquidityTx);
        const totalFundValueAfterDecreaseLiquidity = await poolManagerLogicProxy.totalFundValue();
        // Assert that fund value is unchanged
        checkAlmostSame(totalFundValueBefore, totalFundValueAfterDecreaseLiquidity, 0.00001);
        // Half 50% withdrawal from pool
        await poolLogicProxy.withdraw(sharesBefore.div(2));
        const sharesAfterHalfWithdrawal = await poolLogicProxy.balanceOf(logicOwner.address);
        const totalFundValueAfterHalfWithdrawal = await poolManagerLogicProxy.totalFundValue();
        checkAlmostSame(sharesAfterHalfWithdrawal, sharesBefore.div(2), 0.00001);
        checkAlmostSame(totalFundValueAfterHalfWithdrawal, totalFundValueAfterDecreaseLiquidity.div(2), 0.0001);
        expect(await token0.balanceOf(logicOwner.address)).gt(token0BalanceBefore);
        expect(await token1.balanceOf(logicOwner.address)).gt(token1BalanceBefore);
        // Full 100% withdrawal from pool
        await poolLogicProxy.withdraw(sharesAfterHalfWithdrawal);
        const sharesAfterFullWithdrawal = await poolLogicProxy.balanceOf(logicOwner.address);
        const totalFundValueAfterFullWithdrawal = await poolManagerLogicProxy.totalFundValue();
        expect(sharesAfterFullWithdrawal).eq(0);
        expect(totalFundValueAfterFullWithdrawal).eq(0);
        expect(await token0.balanceOf(logicOwner.address)).gt(token0BalanceBefore);
        expect(await token1.balanceOf(logicOwner.address)).gt(token1BalanceBefore);
      });
    });
  });
};
