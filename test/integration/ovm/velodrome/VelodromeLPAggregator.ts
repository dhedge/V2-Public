import { ethers } from "hardhat";
import { expect } from "chai";

import { ovmChainData } from "../../../../config/chainData/ovmData";
import { utils } from "../../utils/utils";
import { units } from "../../../testHelpers";
import { getAccountToken } from "../../utils/getAccountTokens";
import { PoolFactory } from "../../../../types";
import { deployContracts } from "../../utils/deployContracts/deployContracts";

const { assets, assetsBalanceOfSlot, velodrome, velodromeV2 } = ovmChainData;

type ITestParam = typeof velodromeV2 & { routerContractName: "IVelodromeRouter" | "IVelodromeV2Router" };

const runTests = ({ routerContractName, router, factory, STABLE_USDC_DAI, VARIABLE_WETH_USDC }: ITestParam) => {
  const v2 = routerContractName === "IVelodromeV2Router";

  describe(`Velodrome LP ${v2 ? "V2 " : ""}aggregator Test`, () => {
    let poolFactory: PoolFactory;

    utils.beforeAfterReset(before, after);

    before(async () => {
      const deployment = await deployContracts("ovm");
      poolFactory = deployment.poolFactory;
    });

    it("Check lp price after huge swap (stable lp): VelodromeStableLPAggregator", async () => {
      const [owner] = await ethers.getSigners();

      const VelodromeStableLPAggregator = await ethers.getContractFactory("VelodromeStableLPAggregator");
      const velodromeLPAggregator = await VelodromeStableLPAggregator.deploy(
        STABLE_USDC_DAI.poolAddress,
        poolFactory.address,
      );
      await velodromeLPAggregator.deployed();

      let priceBefore = (await velodromeLPAggregator.latestRoundData())[1];

      const velodromeRouter = await ethers.getContractAt(routerContractName, router);
      const dai = await ethers.getContractAt("@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20", assets.dai);
      const usdc = await ethers.getContractAt("@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20", assets.usdc);

      // USDC/DAI stable pool has little liquidity on V1, try to swap 200K first
      let swapAmount = units(200000, 6);
      await getAccountToken(swapAmount, owner.address, usdc.address, assetsBalanceOfSlot.usdc);

      await usdc.approve(velodromeRouter.address, swapAmount);

      const routes = {
        from: usdc.address,
        to: dai.address,
        stable: STABLE_USDC_DAI.isStable,
      };
      const routesToPass = [v2 ? { ...routes, factory } : routes];
      await velodromeRouter.swapExactTokensForTokens(
        swapAmount,
        0,
        routesToPass,
        owner.address,
        ethers.constants.MaxUint256,
      );

      expect(await dai.balanceOf(owner.address)).to.gt(0);

      let priceAfter = (await velodromeLPAggregator.latestRoundData())[1];

      expect(priceBefore).to.closeTo(priceAfter, priceAfter.div(10000)); // 0.01% diff

      // try to swap 1M
      priceBefore = priceAfter;
      swapAmount = units(1000000, 6);
      await getAccountToken(swapAmount, owner.address, usdc.address, assetsBalanceOfSlot.usdc);
      await usdc.approve(velodromeRouter.address, swapAmount);
      await velodromeRouter.swapExactTokensForTokens(
        swapAmount,
        0,
        routesToPass,
        owner.address,
        ethers.constants.MaxUint256,
      );

      priceAfter = (await velodromeLPAggregator.latestRoundData())[1];

      expect(priceBefore).to.closeTo(priceAfter, priceAfter.div(10000)); // 0.01% diff
    });

    it("Check lp price after huge swap (variable lp): VelodromeVariableLPAggregator", async () => {
      const [owner] = await ethers.getSigners();

      const VelodromeVariableLPAggregator = await ethers.getContractFactory("VelodromeVariableLPAggregator");
      const velodromeLPAggregator = await VelodromeVariableLPAggregator.deploy(
        VARIABLE_WETH_USDC.poolAddress,
        poolFactory.address,
      );
      await velodromeLPAggregator.deployed();

      let priceBefore = (await velodromeLPAggregator.latestRoundData())[1];

      const velodromeRouter = await ethers.getContractAt(routerContractName, router);
      const weth = await ethers.getContractAt("@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20", assets.weth);
      const usdc = await ethers.getContractAt("@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20", assets.usdc);

      // WETH/USDC stable pool has a lot liquidity on V2, little on V1, try to swap 200K first
      let swapAmount = units(200000, 6);
      await getAccountToken(swapAmount, owner.address, usdc.address, assetsBalanceOfSlot.usdc);

      await usdc.approve(velodromeRouter.address, swapAmount);

      const routes = {
        from: usdc.address,
        to: weth.address,
        stable: VARIABLE_WETH_USDC.isStable,
      };
      const routesToPass = [v2 ? { ...routes, factory } : routes];
      await velodromeRouter.swapExactTokensForTokens(
        swapAmount,
        0,
        routesToPass,
        owner.address,
        ethers.constants.MaxUint256,
      );

      expect(await weth.balanceOf(owner.address)).to.gt(0);

      let priceAfter = (await velodromeLPAggregator.latestRoundData())[1];

      expect(priceBefore).to.closeTo(priceAfter, priceAfter.div(10000)); // 0.01% diff

      // try to swap 4M
      priceBefore = priceAfter;
      swapAmount = units(4000000, 6);
      await getAccountToken(swapAmount, owner.address, usdc.address, assetsBalanceOfSlot.usdc);
      await usdc.approve(velodromeRouter.address, swapAmount);
      await velodromeRouter.swapExactTokensForTokens(
        swapAmount,
        0,
        routesToPass,
        owner.address,
        ethers.constants.MaxUint256,
      );

      priceAfter = (await velodromeLPAggregator.latestRoundData())[1];

      expect(priceBefore).to.closeTo(priceAfter, priceAfter.div(10000)); // 0.01% diff
    });
  });
};

[
  {
    ...velodrome,
    routerContractName: "IVelodromeRouter" as const,
  },
  {
    ...velodromeV2,
    routerContractName: "IVelodromeV2Router" as const,
  },
].forEach(runTests);
