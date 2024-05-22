import { ethers } from "hardhat";
import { expect } from "chai";
import { BigNumber } from "ethers";

import {
  IERC20,
  IVelodromeNonfungiblePositionManager,
  PoolFactory,
  PoolLogic,
  PoolManagerLogic,
} from "../../../../types";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { createFund } from "../../utils/createFund";
import { getAccountToken } from "../../utils/getAccountTokens";
import { getCurrentTick, mintLpAsPool, VelodromeCLMintSettings } from "../../utils/velodromeCLUtils";
import { IBackboneDeployments, deployBackboneContracts } from "../../utils/deployContracts/deployBackboneContracts";
import {
  IVelodromeCLTestParams,
  deployVelodromeCLInfrastructure,
  iERC20,
  iERC721,
  iVelodromeCLGauge,
} from "./velodromeCLTestDeploymentHelpers";
import { utils } from "../../utils/utils";
import { checkAlmostSame } from "../../../testHelpers";

const deadLine = Math.floor(Date.now() / 1000 + 100000000);

export const velodromeCLGaugeContractGuardTest = (testParams: IVelodromeCLTestParams) => {
  const { pairs, factory } = testParams;
  const { bothSupportedPair } = pairs;

  describe("Velodrome CL Gauge Guard Test", function () {
    let deployments: IBackboneDeployments;
    let logicOwner: SignerWithAddress, manager: SignerWithAddress;
    let poolFactory: PoolFactory, poolLogicProxy: PoolLogic, poolManagerLogicProxy: PoolManagerLogic;
    let tokenId: BigNumber;
    let PROTOCOL_TOKEN: IERC20;
    let nonfungiblePositionManager: IVelodromeNonfungiblePositionManager;
    let token0: IERC20;
    let token1: IERC20;

    before(async function () {
      deployments = await deployBackboneContracts(testParams);

      manager = deployments.manager;
      logicOwner = deployments.owner;
      poolFactory = deployments.poolFactory;

      ({ nonfungiblePositionManager, PROTOCOL_TOKEN } = await deployVelodromeCLInfrastructure(deployments, testParams));

      const funds = await createFund(
        poolFactory,
        logicOwner,
        manager,
        [
          { asset: bothSupportedPair.token0, isDeposit: true },
          { asset: bothSupportedPair.token1, isDeposit: true },
          { asset: PROTOCOL_TOKEN.address, isDeposit: false },
        ],
        {
          performance: BigNumber.from("0"),
          management: BigNumber.from("0"),
        },
      );
      poolLogicProxy = funds.poolLogicProxy;
      poolManagerLogicProxy = funds.poolManagerLogicProxy;

      await getAccountToken(
        bothSupportedPair.amount0.mul(2),
        logicOwner.address,
        bothSupportedPair.token0,
        bothSupportedPair.token0Slot,
      );
      await getAccountToken(
        bothSupportedPair.amount1.mul(2),
        logicOwner.address,
        bothSupportedPair.token1,
        bothSupportedPair.token1Slot,
      );

      token0 = await ethers.getContractAt("IERC20", bothSupportedPair.token0);
      token1 = await ethers.getContractAt("IERC20", bothSupportedPair.token1);

      await token1.approve(poolLogicProxy.address, bothSupportedPair.amount1.mul(2));
      await token0.approve(poolLogicProxy.address, bothSupportedPair.amount0.mul(2));
      await poolLogicProxy.deposit(bothSupportedPair.token0, bothSupportedPair.amount0.mul(2));

      await poolLogicProxy.deposit(bothSupportedPair.token1, bothSupportedPair.amount1.mul(2));
      let approveABI = iERC20.encodeFunctionData("approve", [
        nonfungiblePositionManager.address,
        bothSupportedPair.amount0,
      ]);
      await poolLogicProxy.connect(manager).execTransaction(bothSupportedPair.token0, approveABI);
      approveABI = iERC20.encodeFunctionData("approve", [
        nonfungiblePositionManager.address,
        bothSupportedPair.amount1,
      ]);
      await poolLogicProxy.connect(manager).execTransaction(bothSupportedPair.token1, approveABI);

      const token0Address = bothSupportedPair.token0;
      const token1Address = bothSupportedPair.token1;
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

      await poolManagerLogicProxy
        .connect(manager)
        .changeAssets([{ asset: nonfungiblePositionManager.address, isDeposit: false }], []);
      await mintLpAsPool(nonfungiblePositionManager.address, poolLogicProxy, manager, mintSettings);

      tokenId = await nonfungiblePositionManager.tokenOfOwnerByIndex(poolLogicProxy.address, 0);

      //approve for staking in gauge
      approveABI = iERC721.encodeFunctionData("approve", [bothSupportedPair.gauge, tokenId]);
      await poolLogicProxy.connect(manager).execTransaction(nonfungiblePositionManager.address, approveABI);
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
        checkAlmostSame(await poolManagerLogicProxy.totalFundValue(), totalFundValueBefore, 0.00001);

        expect(await nonfungiblePositionManager.ownerOf(tokenId)).to.equal(poolLogicProxy.address);
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
        checkAlmostSame(totalFundValueBefore, await poolManagerLogicProxy.totalFundValue(), 0.00001);
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
      it("Should be able to withdraw", async () => {
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
