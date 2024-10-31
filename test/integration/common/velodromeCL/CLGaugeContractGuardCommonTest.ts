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
import { getAccountToken } from "../../utils/getAccountTokens";
import { getCurrentTick, mintLpAsUser, VelodromeCLMintSettings } from "../../utils/velodromeCLUtils";

const deadLine = Math.floor(Date.now() / 1000 + 100000000);

export const clGaugeContractGuardCommonTest = (testParams: IVelodromeCLTestParams) => {
  const { pairs, factory } = testParams;
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

    describe("staking", async () => {
      it("Reverts if nft not in dHEDGE nft tracker", async () => {
        await poolManagerLogicProxy
          .connect(manager)
          .changeAssets([{ asset: PROTOCOL_TOKEN.address, isDeposit: false }], []);
        const depositTx = iVelodromeCLGauge.encodeFunctionData("deposit(uint256)", [1234]);

        await expect(
          poolLogicProxy.connect(manager).execTransaction(bothSupportedPair.gauge, depositTx),
        ).to.revertedWith("position is not tracked");
      });

      it("Can't stake if velo is not supported", async () => {
        const depositTx = iVelodromeCLGauge.encodeFunctionData("deposit(uint256)", [tokenId]);

        await expect(
          poolLogicProxy.connect(manager).execTransaction(bothSupportedPair.gauge, depositTx),
        ).to.revertedWith("unsupported asset: rewardToken");
      });

      it("Reverts if token0 is not supported", async () => {
        await poolManagerLogicProxy
          .connect(manager)
          .changeAssets([{ asset: PROTOCOL_TOKEN.address, isDeposit: false }], []);
        // hack to set token0 balance to 0 for the pool, so we can removed token0 from the supported assets
        const token0BalBefore = await token0.balanceOf(poolLogicProxy.address);
        await getAccountToken(
          BigNumber.from(0),
          poolLogicProxy.address,
          bothSupportedPair.token0,
          bothSupportedPair.token0Slot,
        );
        // remove token0
        await poolManagerLogicProxy.connect(manager).changeAssets([], [bothSupportedPair.token0]);
        // set the token0 balance back
        await getAccountToken(
          token0BalBefore,
          poolLogicProxy.address,
          bothSupportedPair.token0,
          bothSupportedPair.token0Slot,
        );
        const depositTx = iVelodromeCLGauge.encodeFunctionData("deposit(uint256)", [tokenId]);

        await expect(
          poolLogicProxy.connect(manager).execTransaction(bothSupportedPair.gauge, depositTx),
        ).to.revertedWith("unsupported asset: tokenA");
      });

      it("Reverts if token1 is not supported", async () => {
        await poolManagerLogicProxy
          .connect(manager)
          .changeAssets([{ asset: PROTOCOL_TOKEN.address, isDeposit: false }], []);
        // hack to set token1 balance to 0 for the pool, so we can removed token1 from the supported assets
        const token1BalBefore = await token1.balanceOf(poolLogicProxy.address);
        await getAccountToken(
          BigNumber.from(0),
          poolLogicProxy.address,
          bothSupportedPair.token1,
          bothSupportedPair.token1Slot,
        );
        // remove token1
        await poolManagerLogicProxy.connect(manager).changeAssets([], [bothSupportedPair.token1]);
        // set the token1 balance back
        await getAccountToken(
          token1BalBefore,
          poolLogicProxy.address,
          bothSupportedPair.token1,
          bothSupportedPair.token1Slot,
        );
        const depositTx = iVelodromeCLGauge.encodeFunctionData("deposit(uint256)", [tokenId]);

        await expect(
          poolLogicProxy.connect(manager).execTransaction(bothSupportedPair.gauge, depositTx),
        ).to.revertedWith("unsupported asset: tokenB");
      });

      it("Allow deposit", async () => {
        await poolManagerLogicProxy
          .connect(manager)
          .changeAssets([{ asset: PROTOCOL_TOKEN.address, isDeposit: false }], []);
        const depositTx = iVelodromeCLGauge.encodeFunctionData("deposit(uint256)", [tokenId]);

        await poolLogicProxy.connect(manager).execTransaction(bothSupportedPair.gauge, depositTx);

        expect(await nonfungiblePositionManager.ownerOf(tokenId)).to.equal(bothSupportedPair.gauge);
      });
    });

    describe("unstaking", () => {
      beforeEach(async () => {
        await poolManagerLogicProxy
          .connect(manager)
          .changeAssets([{ asset: PROTOCOL_TOKEN.address, isDeposit: false }], []);
      });
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
        await poolManagerLogicProxy
          .connect(manager)
          .changeAssets([{ asset: PROTOCOL_TOKEN.address, isDeposit: false }], []);

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
        await poolManagerLogicProxy
          .connect(manager)
          .changeAssets([{ asset: PROTOCOL_TOKEN.address, isDeposit: false }], []);
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

    describe("decreaseStakedLiquidity and increaseStakedLiquidity(deprecated for Velodrome)", () => {
      beforeEach(async () => {
        await poolManagerLogicProxy
          .connect(manager)
          .changeAssets([{ asset: PROTOCOL_TOKEN.address, isDeposit: false }], []);
      });
      it("Can't call increaseStakedLiquidity", async () => {
        const depositTx = iVelodromeCLGauge.encodeFunctionData("deposit(uint256)", [tokenId]);
        await poolLogicProxy.connect(manager).execTransaction(bothSupportedPair.gauge, depositTx);
        await ethers.provider.send("evm_increaseTime", [3600 * 24]);
        await ethers.provider.send("evm_mine", []);
        const positionBefore = await nonfungiblePositionManager.positions(tokenId);

        const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();
        const increaseStakedLiquidityTx = iVelodromeCLGauge.encodeFunctionData("increaseStakedLiquidity", [
          tokenId,
          bothSupportedPair.amount0,
          bothSupportedPair.amount1,
          0,
          0,
          deadLine,
        ]);
        await expect(
          poolLogicProxy.connect(manager).execTransaction(bothSupportedPair.gauge, increaseStakedLiquidityTx),
        ).to.revertedWith("invalid transaction");

        checkAlmostSame(await poolManagerLogicProxy.totalFundValue(), totalFundValueBefore, 0.0001);

        const positionAfter = await nonfungiblePositionManager.positions(tokenId);

        checkAlmostSame(positionAfter.liquidity, positionBefore.liquidity, 0.000001);
      });

      it("Can't call decreaseStakedLiquidity", async () => {
        await poolManagerLogicProxy
          .connect(manager)
          .changeAssets([{ asset: PROTOCOL_TOKEN.address, isDeposit: false }], []);

        const depositTx = iVelodromeCLGauge.encodeFunctionData("deposit(uint256)", [tokenId]);
        await poolLogicProxy.connect(manager).execTransaction(bothSupportedPair.gauge, depositTx);
        await ethers.provider.send("evm_increaseTime", [3600 * 24]);
        await ethers.provider.send("evm_mine", []);
        const positionBefore = await nonfungiblePositionManager.positions(tokenId);

        const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

        const decreaseStakedLiquidityTx = iVelodromeCLGauge.encodeFunctionData("decreaseStakedLiquidity", [
          tokenId,
          positionBefore.liquidity.div(2),
          0,
          0,
          deadLine,
        ]);

        await expect(
          poolLogicProxy.connect(manager).execTransaction(bothSupportedPair.gauge, decreaseStakedLiquidityTx),
        ).to.revertedWith("invalid transaction");

        checkAlmostSame(await poolManagerLogicProxy.totalFundValue(), totalFundValueBefore, 0.00001);

        const positionAfter = await nonfungiblePositionManager.positions(tokenId);

        checkAlmostSame(positionAfter.liquidity, positionBefore.liquidity, 0.000001);
      });
    });

    describe("NFT deposit", () => {
      it("shouldn't be able to deposit Velo position NFT to the pool", async () => {
        const token0Address = bothSupportedPair.token0;
        const token1Address = bothSupportedPair.token1;

        // Get enough tokens for the LP mint.
        await getAccountToken(
          bothSupportedPair.amount0.mul(4),
          manager.address,
          token0Address,
          bothSupportedPair.token0Slot,
        );
        await getAccountToken(
          bothSupportedPair.amount1.mul(4),
          manager.address,
          token1Address,
          bothSupportedPair.token1Slot,
        );

        const tickSpacing = bothSupportedPair.tickSpacing;
        const tick = await getCurrentTick(factory, bothSupportedPair);
        const mintSettings: VelodromeCLMintSettings = {
          token0: token0Address,
          token1: token1Address,
          tickSpacing,
          amount0: bothSupportedPair.amount0,
          amount1: bothSupportedPair.amount1,
          tickLower: tick - tickSpacing,
          tickUpper: tick + tickSpacing,
        };

        await mintLpAsUser(nonfungiblePositionManager, manager, mintSettings);

        const tokenId = await nonfungiblePositionManager.tokenOfOwnerByIndex(manager.address, 0);
        await poolManagerLogicProxy
          .connect(manager)
          .changeAssets([{ asset: nonfungiblePositionManager.address, isDeposit: true }], []);

        await nonfungiblePositionManager.connect(manager).approve(poolLogicProxy.address, tokenId);

        await expect(
          poolLogicProxy.connect(manager).deposit(nonfungiblePositionManager.address, tokenId),
        ).to.be.revertedWith("NFTs not supported");
      });
    });

    describe("RewardAssetGuard for reward token in Velodrome", () => {
      it("do not allow disable reward asset if VelodromeCL asset is supported asset", async () => {
        // stake
        await poolManagerLogicProxy
          .connect(manager)
          .changeAssets([{ asset: PROTOCOL_TOKEN.address, isDeposit: false }], []);
        const depositTx = iVelodromeCLGauge.encodeFunctionData("deposit(uint256)", [tokenId]);
        await poolLogicProxy.connect(manager).execTransaction(bothSupportedPair.gauge, depositTx);
        expect(await nonfungiblePositionManager.ownerOf(tokenId)).to.equal(bothSupportedPair.gauge);

        // 5 days
        await ethers.provider.send("evm_increaseTime", [3600 * 24 * 5]);
        await ethers.provider.send("evm_mine", []);

        // don't allow remove reward asset even balance is 0
        expect(await PROTOCOL_TOKEN.balanceOf(poolLogicProxy.address)).to.eq(0);
        await expect(
          poolManagerLogicProxy.connect(manager).changeAssets([], [testParams.protocolToken]),
        ).to.revertedWith("remove linked asset first");

        const sharesBefore = await poolLogicProxy.balanceOf(logicOwner.address);
        // user withdrawal will claim rewardToken into pool
        await poolLogicProxy.withdraw(sharesBefore.div(2));
        expect(await PROTOCOL_TOKEN.balanceOf(poolLogicProxy.address)).to.gt(0);
      });
    });
  });
};
