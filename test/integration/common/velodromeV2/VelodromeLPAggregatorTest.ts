import { ethers } from "hardhat";
import { expect } from "chai";

import { utils } from "../../utils/utils";
import { units } from "../../../testHelpers";
import { getAccountToken } from "../../utils/getAccountTokens";
import { IERC20, VelodromeStableLPAggregator, VelodromeVariableLPAggregator } from "../../../../types";
import { IBackboneDeployments, deployBackboneContracts } from "../../utils/deployContracts/deployBackboneContracts";
import { deployVelodromeV2Infrastructure, IVelodromeV2TestParams } from "./velodromeV2TestDeploymentHelpers";

export const runTests = (testParams: IVelodromeV2TestParams) => {
  const { router, factory, STABLE_USDC_DAI, VARIABLE_WETH_USDC, assetsBalanceOfSlot } = testParams;

  describe("VelodromeLPAggregator Test", () => {
    let deployments: IBackboneDeployments;
    let owner: string;
    let USDC: IERC20, DAI: IERC20, WETH: IERC20;
    let velodromeUsdcDaiV2Aggregator: VelodromeStableLPAggregator;
    let velodromeWethUsdcV2Aggregator: VelodromeVariableLPAggregator;

    before(async () => {
      deployments = await deployBackboneContracts(testParams);
      const deploymentData = await deployVelodromeV2Infrastructure(deployments, testParams);

      owner = deployments.owner.address;
      USDC = deployments.assets.USDC;
      DAI = deployments.assets.DAI;
      WETH = deployments.assets.WETH;
      velodromeUsdcDaiV2Aggregator = deploymentData.velodromeUsdcDaiV2Aggregator;
      velodromeWethUsdcV2Aggregator = deploymentData.velodromeWethUsdcV2Aggregator;
    });

    utils.beforeAfterReset(before, after);

    it("Check lp price after huge swap (stable lp): VelodromeStableLPAggregator", async () => {
      let priceBefore = (await velodromeUsdcDaiV2Aggregator.latestRoundData())[1];

      const velodromeRouter = await ethers.getContractAt("IVelodromeV2Router", router);

      // Try to swap 200K first
      let swapAmount = units(200000, 6);
      await getAccountToken(swapAmount, owner, USDC.address, assetsBalanceOfSlot.usdc);

      await USDC.approve(velodromeRouter.address, swapAmount);

      const routes = {
        from: USDC.address,
        to: DAI.address,
        stable: STABLE_USDC_DAI.isStable,
      };
      const routesToPass = [{ ...routes, factory }];
      await velodromeRouter.swapExactTokensForTokens(swapAmount, 0, routesToPass, owner, ethers.constants.MaxUint256);

      expect(await DAI.balanceOf(owner)).to.gt(0);

      let priceAfter = (await velodromeUsdcDaiV2Aggregator.latestRoundData())[1];

      expect(priceBefore).to.closeTo(priceAfter, priceAfter.div(10000)); // 0.01% diff

      // Try to swap 1M
      priceBefore = priceAfter;
      swapAmount = units(1000000, 6);
      await getAccountToken(swapAmount, owner, USDC.address, assetsBalanceOfSlot.usdc);
      await USDC.approve(velodromeRouter.address, swapAmount);
      await velodromeRouter.swapExactTokensForTokens(swapAmount, 0, routesToPass, owner, ethers.constants.MaxUint256);

      priceAfter = (await velodromeUsdcDaiV2Aggregator.latestRoundData())[1];

      expect(priceBefore).to.closeTo(priceAfter, priceAfter.div(10000)); // 0.01% diff
    });

    it("Check lp price after huge swap (variable lp): VelodromeVariableLPAggregator", async () => {
      let priceBefore = (await velodromeWethUsdcV2Aggregator.latestRoundData())[1];

      const velodromeRouter = await ethers.getContractAt("IVelodromeV2Router", router);

      // Try to swap 200K first
      let swapAmount = units(200000, 6);
      await getAccountToken(swapAmount, owner, USDC.address, assetsBalanceOfSlot.usdc);

      await USDC.approve(velodromeRouter.address, swapAmount);

      const routes = {
        from: USDC.address,
        to: WETH.address,
        stable: VARIABLE_WETH_USDC.isStable,
      };
      const routesToPass = [{ ...routes, factory }];
      await velodromeRouter.swapExactTokensForTokens(swapAmount, 0, routesToPass, owner, ethers.constants.MaxUint256);

      expect(await WETH.balanceOf(owner)).to.gt(0);

      let priceAfter = (await velodromeWethUsdcV2Aggregator.latestRoundData())[1];

      expect(priceBefore).to.closeTo(priceAfter, priceAfter.div(10000)); // 0.01% diff

      // Try to swap 4M
      priceBefore = priceAfter;
      swapAmount = units(4000000, 6);
      await getAccountToken(swapAmount, owner, USDC.address, assetsBalanceOfSlot.usdc);
      await USDC.approve(velodromeRouter.address, swapAmount);
      await velodromeRouter.swapExactTokensForTokens(swapAmount, 0, routesToPass, owner, ethers.constants.MaxUint256);

      priceAfter = (await velodromeWethUsdcV2Aggregator.latestRoundData())[1];

      expect(priceBefore).to.closeTo(priceAfter, priceAfter.div(10000)); // 0.01% diff
    });
  });
};
