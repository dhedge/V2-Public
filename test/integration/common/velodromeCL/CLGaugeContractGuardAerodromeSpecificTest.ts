import { ethers } from "hardhat";
import { expect } from "chai";
import { BigNumber } from "ethers";

import { IVelodromeNonfungiblePositionManager, PoolLogic, PoolManagerLogic } from "../../../../types";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { IVelodromeCLTestParams, iVelodromeCLGauge } from "./velodromeCLTestDeploymentHelpers";
import { utils } from "../../utils/utils";
import { checkAlmostSame } from "../../../testHelpers";
import { setupGaugeContractGuardTestBefore } from "./CLGaugeContractGuardTestHelpers";

const deadLine = Math.floor(Date.now() / 1000 + 100000000);

export const clGaugeContractGuardAerodromeSpecificTest = (testParams: IVelodromeCLTestParams) => {
  const { pairs } = testParams;
  const { bothSupportedPair } = pairs;

  describe("Aerodrome CL Gauge Guard Specific Test", function () {
    let manager: SignerWithAddress;
    let poolLogicProxy: PoolLogic, poolManagerLogicProxy: PoolManagerLogic;
    let tokenId: BigNumber;
    let nonfungiblePositionManager: IVelodromeNonfungiblePositionManager;

    before(async function () {
      ({ manager, poolLogicProxy, poolManagerLogicProxy, tokenId, nonfungiblePositionManager } =
        await setupGaugeContractGuardTestBefore(testParams));
    });

    utils.beforeAfterReset(beforeEach, afterEach);

    describe("decreaseStakedLiquidity and increaseStakedLiquidity(only for Velodrome)", () => {
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
  });
};
