import { ethers } from "hardhat";
import { expect } from "chai";
import { BigNumber } from "ethers";

import {
  IERC20,
  IVelodromeNonfungiblePositionManager,
  IVelodromeNonfungiblePositionManager__factory,
  PoolLogic,
  PoolManagerLogic,
} from "../../../../types";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { IVelodromeCLTestParams, iERC721, iVelodromeCLGauge } from "./velodromeCLTestDeploymentHelpers";
import { utils } from "../../utils/utils";
import { checkAlmostSame } from "../../../testHelpers";
import { setupGaugeContractGuardTestBefore } from "./CLGaugeContractGuardTestHelpers";

const deadLine = Math.floor(Date.now() / 1000 + 100000000);

export const clGaugeContractGuardCommonTest = (testParams: IVelodromeCLTestParams) => {
  const { pairs } = testParams;
  const { bothSupportedPair } = pairs;

  describe("Velodrome/Aerodrome CL Gauge Guard Common Test", function () {
    let logicOwner: SignerWithAddress, manager: SignerWithAddress;
    let poolLogicProxy: PoolLogic, poolManagerLogicProxy: PoolManagerLogic;
    let tokenId: BigNumber;
    let PROTOCOL_TOKEN: IERC20;
    let nonfungiblePositionManager: IVelodromeNonfungiblePositionManager;
    const iNonfungiblePositionManager = new ethers.utils.Interface(IVelodromeNonfungiblePositionManager__factory.abi);
    let token0: IERC20;
    let token1: IERC20;

    before(async function () {
      ({
        logicOwner,
        manager,
        poolLogicProxy,
        poolManagerLogicProxy,
        tokenId,
        PROTOCOL_TOKEN,
        nonfungiblePositionManager,
        token0,
        token1,
      } = await setupGaugeContractGuardTestBefore(testParams));
    });

    utils.beforeAfterReset(beforeEach, afterEach);

    describe("staking", () => {
      it("Reverts if nft not in dHEDGE nft tracker", async () => {
        const depositTx = iVelodromeCLGauge.encodeFunctionData("deposit(uint256)", [1234]);

        await expect(
          poolLogicProxy.connect(manager).execTransaction(bothSupportedPair.gauge, depositTx),
        ).to.revertedWith("position is not tracked");
      });

      it("Allow deposit", async () => {
        const depositTx = iVelodromeCLGauge.encodeFunctionData("deposit(uint256)", [tokenId]);

        await poolLogicProxy.connect(manager).execTransaction(bothSupportedPair.gauge, depositTx);

        expect(await nonfungiblePositionManager.ownerOf(tokenId)).to.equal(bothSupportedPair.gauge);
      });
    });

    describe("unstaking", () => {
      it("Reverts if nft not in dHEDGE nft tracker", async () => {
        const withdrawTx = iVelodromeCLGauge.encodeFunctionData("withdraw", [1234]);

        await expect(
          poolLogicProxy.connect(manager).execTransaction(bothSupportedPair.gauge, withdrawTx),
        ).to.revertedWith("position is not tracked");
      });

      it("Allow withdraw", async () => {
        const depositTx = iVelodromeCLGauge.encodeFunctionData("deposit(uint256)", [tokenId]);
        await poolLogicProxy.connect(manager).execTransaction(bothSupportedPair.gauge, depositTx);
        await ethers.provider.send("evm_increaseTime", [3600 * 24]);
        await ethers.provider.send("evm_mine", []);
        const withdrawTx = iVelodromeCLGauge.encodeFunctionData("withdraw", [tokenId]);

        const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();
        await poolLogicProxy.connect(manager).execTransaction(bothSupportedPair.gauge, withdrawTx);
        checkAlmostSame(await poolManagerLogicProxy.totalFundValue(), totalFundValueBefore, 0.0001);

        expect(await nonfungiblePositionManager.ownerOf(tokenId)).to.equal(poolLogicProxy.address);
      });
    });

    describe("getReward", () => {
      beforeEach(async () => {
        const depositTx = iVelodromeCLGauge.encodeFunctionData("deposit(uint256)", [tokenId]);
        await poolLogicProxy.connect(manager).execTransaction(bothSupportedPair.gauge, depositTx);

        // increase time by 1 day
        await ethers.provider.send("evm_increaseTime", [3600 * 24]);
        await ethers.provider.send("evm_mine", []);
      });

      it("Reverts if invalid token id", async () => {
        const claimTx = iVelodromeCLGauge.encodeFunctionData("getReward(uint256)", [1234]);

        await expect(poolLogicProxy.connect(manager).execTransaction(bothSupportedPair.gauge, claimTx)).to.revertedWith(
          "position is not tracked",
        );
      });

      it("Allow claim", async () => {
        const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();
        const claimTx = iVelodromeCLGauge.encodeFunctionData("getReward(uint256)", [tokenId]);
        await poolLogicProxy.connect(manager).execTransaction(bothSupportedPair.gauge, claimTx);
        checkAlmostSame(totalFundValueBefore, await poolManagerLogicProxy.totalFundValue(), 0.0001);
        expect(await PROTOCOL_TOKEN.balanceOf(poolLogicProxy.address)).to.gt(0);
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
      it("Should be able to withdraw(after decreaseLiquidity)", async () => {
        const sharesBefore = await poolLogicProxy.balanceOf(logicOwner.address);
        const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();
        const token0BalanceBefore = await token0.balanceOf(logicOwner.address);
        const token1BalanceBefore = await token1.balanceOf(logicOwner.address);
        // First decrease half the liquidity and move it to the fees to ensure both liquidity and fees get withdrawn correctly
        const positionBefore = await nonfungiblePositionManager.positions(tokenId);

        // unstake
        const withdrawTx = iVelodromeCLGauge.encodeFunctionData("withdraw", [tokenId]);
        await poolLogicProxy.connect(manager).execTransaction(bothSupportedPair.gauge, withdrawTx);

        // decrease LP position by 50%
        const decreaseLiquidityABI = iNonfungiblePositionManager.encodeFunctionData("decreaseLiquidity", [
          [tokenId, positionBefore.liquidity.div(2), 0, 0, deadLine],
        ]);
        await poolLogicProxy.connect(manager).execTransaction(nonfungiblePositionManager.address, decreaseLiquidityABI);

        // stake back
        //approve for staking in gauge
        const approveABI = iERC721.encodeFunctionData("approve", [bothSupportedPair.gauge, tokenId]);
        await poolLogicProxy.connect(manager).execTransaction(nonfungiblePositionManager.address, approveABI);
        const depositTx = iVelodromeCLGauge.encodeFunctionData("deposit(uint256)", [tokenId]);
        await poolLogicProxy.connect(manager).execTransaction(bothSupportedPair.gauge, depositTx);

        const totalFundValueAfterDecreaseLiquidity = await poolManagerLogicProxy.totalFundValue();
        // Assert that fund value is unchanged
        checkAlmostSame(totalFundValueBefore, totalFundValueAfterDecreaseLiquidity, 0.0001);
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
