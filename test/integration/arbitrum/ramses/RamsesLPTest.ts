import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { AssertionError, expect } from "chai";
import { BigNumber } from "ethers";
import { ethers } from "hardhat";

import { units } from "../../../testHelpers";
import {
  IERC20,
  IERC20Extended,
  IERC20__factory,
  IVelodromeRouter__factory,
  IVelodromeGauge__factory,
  PoolLogic,
  PoolManagerLogic,
  IVelodromeGauge,
  IXRam__factory,
} from "../../../../types";
import { createFund } from "../../utils/createFund";
import { arbitrumChainData } from "../../../../config/chainData/arbitrumData";
import { getAccountToken } from "../../utils/getAccountTokens";
import { utils } from "../../utils/utils";
import { IBackboneDeployments, deployBackboneContracts } from "../../utils/deployContracts/deployBackboneContracts";
import { getTokenPriceFromCoingecko } from "../../utils/coingecko/getTokenPrice";

import { deployRamsesInfrastructure } from "./deploymentTestHelpers";

const iERC20 = new ethers.utils.Interface(IERC20__factory.abi);
const iVelodromeRouter = new ethers.utils.Interface(IVelodromeRouter__factory.abi);
const iVelodromeGauge = new ethers.utils.Interface(IVelodromeGauge__factory.abi);
const iXRam = new ethers.utils.Interface(IXRam__factory.abi);

// This is only to make things easier to reuse for other chains
const chainTestData = {
  assets: arbitrumChainData.assets,
  usdPriceFeeds: arbitrumChainData.usdPriceFeeds,
  ramsesVoter: arbitrumChainData.ramses.voter,
  ramsesRouter: arbitrumChainData.ramses.router,
  ram: arbitrumChainData.assets.ram,
  xoRam: arbitrumChainData.ramses.xoRAM,
  token0token1Pair_1: arbitrumChainData.ramses.wstETH_swETH.pairAddress, // crAMM-WSTETH/swETH (stub)
  token0token1Gauge_1: arbitrumChainData.ramses.wstETH_swETH.gaugeAddress,

  // token0token1Pair: arbitrumChainData.ramses.FRAX_alUSD.pairAddress,
  // token0token1Gauge: arbitrumChainData.ramses.FRAX_alUSD.gaugeAddress,
  // token0token1IsStable: arbitrumChainData.ramses.FRAX_alUSD.isStable,
  // token0: arbitrumChainData.assets.frax, // to be priced against (has Chainlink price feed)
  // token1: arbitrumChainData.assets.alusd, // to be priced
  // usdPriceFeedToken0: arbitrumChainData.usdPriceFeeds.frax,
  // token0Slot: arbitrumChainData.assetsBalanceOfSlot.frax,
  // token1Slot: arbitrumChainData.assetsBalanceOfSlot.alusd,

  token0token1Pair: arbitrumChainData.ramses.USDC_swETH.pairAddress,
  token0token1Gauge: arbitrumChainData.ramses.USDC_swETH.gaugeAddress,
  token0token1IsStable: arbitrumChainData.ramses.USDC_swETH.isStable,
  token0: arbitrumChainData.assets.usdcnative, // to be priced against (has Chainlink price feed)
  token1: arbitrumChainData.assets.sweth, // to be priced
  usdPriceFeedToken0: arbitrumChainData.usdPriceFeeds.usdc,
  token0Slot: arbitrumChainData.assetsBalanceOfSlot.usdcnative,
  token1Slot: arbitrumChainData.assetsBalanceOfSlot.sweth,
};

export type RamsesTestData = typeof chainTestData;

describe("RamsesLPTest", () => {
  let deployments: IBackboneDeployments;
  let token1TWAPAggregator: Awaited<ReturnType<typeof deployRamsesInfrastructure>>["token1TWAPAggregator"];
  let token0tokenLPAggregator: Awaited<ReturnType<typeof deployRamsesInfrastructure>>["token0tokenLPAggregator"];

  let TOKEN0: IERC20Extended, TOKEN1: IERC20Extended, RAMSES_PAIR: IERC20, RAM: IERC20, xoRAM: IERC20;
  let decimals0: number, decimals1: number;
  let RAMSES_GAUGE: IVelodromeGauge;
  let manager: SignerWithAddress;
  let poolLogicProxy: PoolLogic;
  let poolManagerLogicProxy: PoolManagerLogic;
  let lpAmount: BigNumber;

  before(async () => {
    deployments = await deployBackboneContracts(chainTestData);
    const aggregators = await deployRamsesInfrastructure(deployments, chainTestData);
    token1TWAPAggregator = aggregators.token1TWAPAggregator;
    token0tokenLPAggregator = aggregators.token0tokenLPAggregator;
    manager = deployments.manager;

    TOKEN0 = <IERC20Extended>await ethers.getContractAt("IERC20Extended", chainTestData.token0);
    TOKEN1 = <IERC20Extended>await ethers.getContractAt("IERC20Extended", chainTestData.token1);
    decimals0 = await TOKEN0.decimals();
    decimals1 = await TOKEN1.decimals();
    RAMSES_PAIR = <IERC20>(
      await ethers.getContractAt(
        "@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20",
        chainTestData.token0token1Pair,
      )
    );
    RAM = <IERC20>(
      await ethers.getContractAt("@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20", chainTestData.ram)
    );
    xoRAM = <IERC20>(
      await ethers.getContractAt("@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20", chainTestData.xoRam)
    );
    RAMSES_GAUGE = <IVelodromeGauge>await ethers.getContractAt("IVelodromeGauge", chainTestData.token0token1Gauge);

    await getAccountToken(
      units(10_000, decimals0),
      deployments.owner.address,
      TOKEN0.address,
      chainTestData.token0Slot,
    );
    await getAccountToken(
      units(10_000, decimals1),
      deployments.owner.address,
      TOKEN1.address,
      chainTestData.token1Slot,
    );

    const funds = await createFund(deployments.poolFactory, deployments.owner, manager, [
      { asset: TOKEN0.address, isDeposit: true },
      { asset: TOKEN1.address, isDeposit: true },
      { asset: RAMSES_PAIR.address, isDeposit: false },
      { asset: chainTestData.token0token1Pair_1, isDeposit: false },
    ]);
    poolLogicProxy = funds.poolLogicProxy;
    poolManagerLogicProxy = funds.poolManagerLogicProxy;

    await TOKEN0.approve(poolLogicProxy.address, units(200, decimals0));
    await poolLogicProxy.deposit(TOKEN0.address, units(200, decimals0));

    await TOKEN1.approve(poolLogicProxy.address, units(200, decimals1));
    await poolLogicProxy.deposit(TOKEN1.address, units(200, decimals1));

    const getApproveTxData = (decimals: number) =>
      iERC20.encodeFunctionData("approve", [chainTestData.ramsesRouter, units(200, decimals)]);
    await poolLogicProxy.connect(manager).execTransaction(TOKEN0.address, getApproveTxData(decimals0));
    await poolLogicProxy.connect(manager).execTransaction(TOKEN1.address, getApproveTxData(decimals1));

    const addLiquidityTx = iVelodromeRouter.encodeFunctionData("addLiquidity", [
      TOKEN0.address,
      TOKEN1.address,
      chainTestData.token0token1IsStable,
      units(100, decimals0),
      units(100, decimals1),
      0,
      0,
      poolLogicProxy.address,
      ethers.constants.MaxUint256,
    ]);
    await poolLogicProxy.connect(manager).execTransaction(chainTestData.ramsesRouter, addLiquidityTx);

    lpAmount = await RAMSES_PAIR.balanceOf(poolLogicProxy.address);

    await poolLogicProxy
      .connect(manager)
      .execTransaction(RAMSES_PAIR.address, iERC20.encodeFunctionData("approve", [RAMSES_GAUGE.address, lpAmount]));
  });

  utils.beforeAfterReset(beforeEach, afterEach);

  describe("RamsesGaugeContractGuardTest", () => {
    describe("deposit", () => {
      it("Reverts if lp asset is not supported", async () => {
        await poolManagerLogicProxy.connect(manager).changeAssets([], [chainTestData.token0token1Pair_1]);
        const depositTx = iVelodromeGauge.encodeFunctionData("deposit", [lpAmount, 0]);

        await expect(
          poolLogicProxy.connect(manager).execTransaction(chainTestData.token0token1Gauge_1, depositTx),
        ).to.revertedWith("unsupported lp asset");
      });

      it("Allows deposit", async () => {
        const depositTx = iVelodromeGauge.encodeFunctionData("deposit", [lpAmount, 0]);

        await poolLogicProxy.connect(manager).execTransaction(RAMSES_GAUGE.address, depositTx);

        expect(await RAMSES_PAIR.balanceOf(poolLogicProxy.address)).to.equal(0);
      });
    });

    describe("depositAll", async () => {
      it("Reverts if lp asset is not supported", async () => {
        await poolManagerLogicProxy.connect(manager).changeAssets([], [chainTestData.token0token1Pair_1]);
        const depositTx = iVelodromeGauge.encodeFunctionData("depositAll", [0]);

        await expect(
          poolLogicProxy.connect(manager).execTransaction(chainTestData.token0token1Gauge_1, depositTx),
        ).to.revertedWith("unsupported lp asset");
      });

      it("Allows depositAll", async () => {
        const depositTx = iVelodromeGauge.encodeFunctionData("depositAll", [0]);

        await poolLogicProxy.connect(manager).execTransaction(RAMSES_GAUGE.address, depositTx);

        expect(await RAMSES_PAIR.balanceOf(poolLogicProxy.address)).to.equal(0);
      });
    });

    describe("withdraw", () => {
      beforeEach(async () => {
        const depositTx = iVelodromeGauge.encodeFunctionData("deposit", [lpAmount, 0]);
        await poolLogicProxy.connect(manager).execTransaction(RAMSES_GAUGE.address, depositTx);
      });

      it("Reverts if lp asset is not supported", async () => {
        await poolManagerLogicProxy.connect(manager).changeAssets([], [chainTestData.token0token1Pair_1]);
        const withdrawTx = iVelodromeGauge.encodeFunctionData("withdraw", [lpAmount]);

        await expect(
          poolLogicProxy.connect(manager).execTransaction(chainTestData.token0token1Gauge_1, withdrawTx),
        ).to.revertedWith("unsupported lp asset");
      });

      it("Allows withdraw", async () => {
        const withdrawTx = iVelodromeGauge.encodeFunctionData("withdraw", [lpAmount]);

        await poolLogicProxy.connect(manager).execTransaction(RAMSES_GAUGE.address, withdrawTx);

        expect(await RAMSES_PAIR.balanceOf(poolLogicProxy.address)).to.equal(lpAmount);
      });
    });

    describe("withdrawAll", () => {
      beforeEach(async () => {
        const depositTx = iVelodromeGauge.encodeFunctionData("deposit", [lpAmount, 0]);
        await poolLogicProxy.connect(manager).execTransaction(RAMSES_GAUGE.address, depositTx);
      });

      it("Reverts if lp asset is not supported", async () => {
        await poolManagerLogicProxy.connect(manager).changeAssets([], [chainTestData.token0token1Pair_1]);
        const withdrawTx = iVelodromeGauge.encodeFunctionData("withdrawAll", []);

        await expect(
          poolLogicProxy.connect(manager).execTransaction(chainTestData.token0token1Gauge_1, withdrawTx),
        ).to.revertedWith("unsupported lp asset");
      });

      it("Allows withdrawAll", async () => {
        const withdrawTx = iVelodromeGauge.encodeFunctionData("withdrawAll", []);

        await poolLogicProxy.connect(manager).execTransaction(RAMSES_GAUGE.address, withdrawTx);

        expect(await RAMSES_PAIR.balanceOf(poolLogicProxy.address)).to.equal(lpAmount);
      });
    });

    describe("getReward", () => {
      beforeEach(async () => {
        const depositTx = iVelodromeGauge.encodeFunctionData("deposit", [lpAmount, 0]);
        await poolLogicProxy.connect(manager).execTransaction(RAMSES_GAUGE.address, depositTx);

        await ethers.provider.send("evm_increaseTime", [3600 * 24]); // 1 day
        await ethers.provider.send("evm_mine", []);
      });

      it("Reverts if invalid claimer", async () => {
        const claimTx = iVelodromeGauge.encodeFunctionData("getReward", [deployments.user.address, [RAM.address]]);

        await expect(poolLogicProxy.connect(manager).execTransaction(RAMSES_GAUGE.address, claimTx)).to.revertedWith(
          "invalid claimer",
        );
      });

      it("Allows claim", async () => {
        const claimTx = iVelodromeGauge.encodeFunctionData("getReward", [
          poolLogicProxy.address,
          [RAM.address, xoRAM.address],
        ]);

        await poolLogicProxy.connect(manager).execTransaction(RAMSES_GAUGE.address, claimTx);

        expect(await RAM.balanceOf(poolLogicProxy.address)).to.gt(0);
        expect(await xoRAM.balanceOf(poolLogicProxy.address)).to.gt(0);
      });
    });
  });

  describe("withdrawProcessing", () => {
    beforeEach(async () => {
      const depositTx = iVelodromeGauge.encodeFunctionData("deposit", [lpAmount, 0]);
      await poolLogicProxy.connect(manager).execTransaction(RAMSES_GAUGE.address, depositTx);

      await deployments.poolFactory.setExitCooldown(0);
      await deployments.assetHandler.setChainlinkTimeout(86400 * 7); // 7 days expiry
      await ethers.provider.send("evm_increaseTime", [3600 * 24 * 3]); // 3 days
      await ethers.provider.send("evm_mine", []);
    });

    it("Pool has expected funds after withdraw", async () => {
      const token0BalanceBefore = await TOKEN0.balanceOf(poolLogicProxy.address);
      const token1BalanceBefore = await TOKEN1.balanceOf(poolLogicProxy.address);
      const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();
      const gaugeBalanceBefore = await RAMSES_GAUGE.balanceOf(poolLogicProxy.address);

      // withdraw half
      await poolLogicProxy.withdraw((await poolLogicProxy.balanceOf(deployments.owner.address)).div(2));

      expect(await TOKEN0.balanceOf(poolLogicProxy.address)).to.be.closeTo(
        token0BalanceBefore.div(2),
        token0BalanceBefore.div(2).div(2_000), // 0.05%
      );
      expect(await TOKEN1.balanceOf(poolLogicProxy.address)).to.be.closeTo(
        token1BalanceBefore.div(2),
        token1BalanceBefore.div(2).div(2_000), // 0.05%
      );
      expect(await poolManagerLogicProxy.totalFundValue()).to.be.closeTo(
        totalFundValueBefore.div(2),
        totalFundValueBefore.div(2).div(2_000), // 0.05%
      );
      expect(await RAMSES_GAUGE.balanceOf(poolLogicProxy.address)).to.be.closeTo(
        gaugeBalanceBefore.div(2),
        gaugeBalanceBefore.div(2).div(2_000), // 0.05%
      );
    });

    it("Claiming rewards shouldn't happen if reward tokens not supported", async () => {
      const claimAmountRAM = await RAMSES_GAUGE.earned(RAM.address, poolLogicProxy.address);
      const claimAmountXRAM = await RAMSES_GAUGE.earned(xoRAM.address, poolLogicProxy.address);
      expect(claimAmountRAM).to.gt(0);
      expect(claimAmountXRAM).to.gt(0);

      // withdraw half
      await poolLogicProxy.withdraw((await poolLogicProxy.balanceOf(deployments.owner.address)).div(2));

      expect(await RAM.balanceOf(poolLogicProxy.address)).to.be.equal(0);
      expect(await xoRAM.balanceOf(poolLogicProxy.address)).to.be.equal(0);
      expect(await RAMSES_GAUGE.earned(RAM.address, poolLogicProxy.address)).to.gte(claimAmountRAM);
      expect(await RAMSES_GAUGE.earned(xoRAM.address, poolLogicProxy.address)).to.gte(claimAmountXRAM);
    });

    it("Withdrawer receives their portion of LP Tokens and doesn't receive rewards portion if reward tokens not supported", async () => {
      // withdraw half
      await poolLogicProxy.withdraw((await poolLogicProxy.balanceOf(deployments.owner.address)).div(2));

      expect(await RAMSES_PAIR.balanceOf(deployments.owner.address)).to.be.closeTo(
        lpAmount.div(2),
        lpAmount.div(2).div(2_000), // 0.05%
      );
      expect(await RAM.balanceOf(deployments.owner.address)).to.be.equal(0);
      expect(await xoRAM.balanceOf(deployments.owner.address)).to.be.equal(0);
    });
  });

  describe("getBalance", () => {
    it("Prices underlying LP token correctly", async () => {
      let totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

      const addLiquidityTx = iVelodromeRouter.encodeFunctionData("addLiquidity", [
        TOKEN0.address,
        TOKEN1.address,
        chainTestData.token0token1IsStable,
        units(100, decimals0),
        units(100, decimals1),
        0,
        0,
        poolLogicProxy.address,
        ethers.constants.MaxUint256,
      ]);
      await poolLogicProxy.connect(manager).execTransaction(chainTestData.ramsesRouter, addLiquidityTx);

      // price change between chainlink & amm, threshold
      expect(await poolManagerLogicProxy.totalFundValue()).to.be.closeTo(
        totalFundValueBefore,
        totalFundValueBefore.div(1_000), // 0.1%
      );

      lpAmount = await RAMSES_PAIR.balanceOf(poolLogicProxy.address);

      totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();
      const token0BalanceBefore = await TOKEN0.balanceOf(poolLogicProxy.address);
      const token1BalanceBefore = await TOKEN1.balanceOf(poolLogicProxy.address);

      const approveTx = iERC20.encodeFunctionData("approve", [RAMSES_GAUGE.address, lpAmount]);
      await poolLogicProxy.connect(manager).execTransaction(RAMSES_PAIR.address, approveTx);

      const depositTx = iVelodromeGauge.encodeFunctionData("deposit", [lpAmount.div(2), 0]);
      await poolLogicProxy.connect(manager).execTransaction(RAMSES_GAUGE.address, depositTx);

      expect(await RAMSES_PAIR.balanceOf(poolLogicProxy.address)).to.be.closeTo(lpAmount.div(2), 1);
      expect(await TOKEN0.balanceOf(poolLogicProxy.address)).to.be.eq(token0BalanceBefore);
      expect(await TOKEN1.balanceOf(poolLogicProxy.address)).to.be.eq(token1BalanceBefore);
      expect(await poolManagerLogicProxy.totalFundValue()).to.be.closeTo(
        totalFundValueBefore,
        totalFundValueBefore.div(1_000),
      ); // 0.1%
    });

    // can be added back once we support reward tokens in our system
    it.skip("Includes unclaimed rewards in Price", async () => {
      const depositTx = iVelodromeGauge.encodeFunctionData("deposit", [lpAmount, 0]);
      await poolLogicProxy.connect(manager).execTransaction(RAMSES_GAUGE.address, depositTx);

      const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

      await deployments.assetHandler.setChainlinkTimeout(86400 * 7); // 7 days expiry
      await ethers.provider.send("evm_increaseTime", [3600 * 24]); // 1 day
      await ethers.provider.send("evm_mine", []);

      const claimAmount = await RAMSES_GAUGE.earned(RAM.address, poolLogicProxy.address);
      expect(claimAmount).to.gt(0);
      expect(await poolManagerLogicProxy.totalFundValue()).to.closeTo(
        totalFundValueBefore.add(await poolManagerLogicProxy["assetValue(address,uint256)"](RAM.address, claimAmount)),
        await poolManagerLogicProxy["assetValue(address,uint256)"](RAM.address, claimAmount.div(1000)),
      );
    });
  });

  describe("RamsesRouterContractGuardTest addLiquidity", () => {
    it("Reverts if tokenA is not supported asset", async () => {
      const addLiquidityTx = iVelodromeRouter.encodeFunctionData("addLiquidity", [
        chainTestData.assets.weth,
        TOKEN1.address,
        chainTestData.token0token1IsStable,
        units(100, decimals0),
        units(100, decimals1),
        0,
        0,
        poolLogicProxy.address,
        ethers.constants.MaxUint256,
      ]);
      await expect(
        poolLogicProxy.connect(manager).execTransaction(chainTestData.ramsesRouter, addLiquidityTx),
      ).to.revertedWith("unsupported asset: tokenA");
    });

    it("Reverts if tokenB is not supported asset", async () => {
      const addLiquidityTx = iVelodromeRouter.encodeFunctionData("addLiquidity", [
        TOKEN0.address,
        chainTestData.assets.weth,
        chainTestData.token0token1IsStable,
        units(100, decimals0),
        units(100, decimals1),
        0,
        0,
        poolLogicProxy.address,
        ethers.constants.MaxUint256,
      ]);
      await expect(
        poolLogicProxy.connect(manager).execTransaction(chainTestData.ramsesRouter, addLiquidityTx),
      ).to.revertedWith("unsupported asset: tokenB");
    });

    it("Reverts if lp asset is not supported asset", async () => {
      const addLiquidityTx = iVelodromeRouter.encodeFunctionData("addLiquidity", [
        TOKEN0.address,
        TOKEN1.address,
        !chainTestData.token0token1IsStable,
        units(100, decimals0),
        units(100, decimals1),
        0,
        0,
        poolLogicProxy.address,
        ethers.constants.MaxUint256,
      ]);
      await expect(
        poolLogicProxy.connect(manager).execTransaction(chainTestData.ramsesRouter, addLiquidityTx),
      ).to.revertedWith("unsupported lp asset");
    });

    it("Reverts if recipient is not pool logic", async () => {
      const addLiquidityTx = iVelodromeRouter.encodeFunctionData("addLiquidity", [
        TOKEN0.address,
        TOKEN1.address,
        chainTestData.token0token1IsStable,
        units(100, decimals0),
        units(100, decimals1),
        0,
        0,
        deployments.user.address,
        ethers.constants.MaxUint256,
      ]);
      await expect(
        poolLogicProxy.connect(manager).execTransaction(chainTestData.ramsesRouter, addLiquidityTx),
      ).to.revertedWith("recipient is not pool");
    });

    it("Allows add liquidity", async () => {
      const addLiquidityTx = iVelodromeRouter.encodeFunctionData("addLiquidity", [
        TOKEN0.address,
        TOKEN1.address,
        chainTestData.token0token1IsStable,
        units(100, decimals0),
        units(100, decimals1),
        0,
        0,
        poolLogicProxy.address,
        ethers.constants.MaxUint256,
      ]);

      const liquidityBefore = await RAMSES_PAIR.balanceOf(poolLogicProxy.address);

      await poolLogicProxy.connect(manager).execTransaction(chainTestData.ramsesRouter, addLiquidityTx);

      const liquidityAfter = await RAMSES_PAIR.balanceOf(poolLogicProxy.address);

      expect(liquidityAfter).to.be.gt(liquidityBefore);
    });
  });

  describe("RamsesRouterContractGuardTest removeLiquidity", () => {
    it("Reverts if tokenA is not supported asset", async () => {
      const removeLiquidityTx = iVelodromeRouter.encodeFunctionData("removeLiquidity", [
        chainTestData.assets.weth,
        TOKEN1.address,
        chainTestData.token0token1IsStable,
        lpAmount,
        0,
        0,
        poolLogicProxy.address,
        ethers.constants.MaxUint256,
      ]);
      await expect(
        poolLogicProxy.connect(manager).execTransaction(chainTestData.ramsesRouter, removeLiquidityTx),
      ).to.revertedWith("unsupported asset: tokenA");
    });

    it("Reverts if tokenB is not supported asset", async () => {
      const removeLiquidityTx = iVelodromeRouter.encodeFunctionData("removeLiquidity", [
        TOKEN0.address,
        chainTestData.assets.weth,
        chainTestData.token0token1IsStable,
        lpAmount,
        0,
        0,
        poolLogicProxy.address,
        ethers.constants.MaxUint256,
      ]);
      await expect(
        poolLogicProxy.connect(manager).execTransaction(chainTestData.ramsesRouter, removeLiquidityTx),
      ).to.revertedWith("unsupported asset: tokenB");
    });

    it("Reverts if lp asset is not supported asset", async () => {
      const removeLiquidityTx = iVelodromeRouter.encodeFunctionData("removeLiquidity", [
        TOKEN0.address,
        TOKEN1.address,
        !chainTestData.token0token1IsStable,
        lpAmount,
        0,
        0,
        poolLogicProxy.address,
        ethers.constants.MaxUint256,
      ]);
      await expect(
        poolLogicProxy.connect(manager).execTransaction(chainTestData.ramsesRouter, removeLiquidityTx),
      ).to.revertedWith("unsupported lp asset");
    });

    it("Reverts if recipient is not pool logic", async () => {
      const removeLiquidityTx = iVelodromeRouter.encodeFunctionData("removeLiquidity", [
        TOKEN0.address,
        TOKEN1.address,
        chainTestData.token0token1IsStable,
        lpAmount,
        0,
        0,
        deployments.user.address,
        ethers.constants.MaxUint256,
      ]);
      await expect(
        poolLogicProxy.connect(manager).execTransaction(chainTestData.ramsesRouter, removeLiquidityTx),
      ).to.revertedWith("recipient is not pool");
    });

    it("Allows remove liquidity", async () => {
      const approveTx = iERC20.encodeFunctionData("approve", [chainTestData.ramsesRouter, lpAmount]);
      await poolLogicProxy.connect(manager).execTransaction(RAMSES_PAIR.address, approveTx);
      lpAmount = await RAMSES_PAIR.balanceOf(poolLogicProxy.address);

      const removeLiquidityTx = iVelodromeRouter.encodeFunctionData("removeLiquidity", [
        TOKEN0.address,
        TOKEN1.address,
        chainTestData.token0token1IsStable,
        lpAmount,
        0,
        0,
        poolLogicProxy.address,
        ethers.constants.MaxUint256,
      ]);

      const liquidityBefore = await RAMSES_PAIR.balanceOf(poolLogicProxy.address);

      await poolLogicProxy.connect(manager).execTransaction(chainTestData.ramsesRouter, removeLiquidityTx);

      const liquidityAfter = await RAMSES_PAIR.balanceOf(poolLogicProxy.address);

      expect(liquidityAfter).to.lt(liquidityBefore);
      expect(liquidityAfter).to.equal(0);
    });
  });

  describe("RamsesTWAPAggregatorTest", () => {
    it("should calculate price correctly", async function () {
      try {
        const price = (await token1TWAPAggregator.latestRoundData())[1];
        console.log("TWAP price: ", price.toString());
        const priceFromCoingecko = ethers.utils.parseUnits(
          (await getTokenPriceFromCoingecko(TOKEN1.address, "arbitrum-one")).toString(),
          8,
        );
        console.log("Coingecko price: ", priceFromCoingecko.toString());
        expect(price).to.be.closeTo(priceFromCoingecko, priceFromCoingecko.div(50)); // 2% - huge difference
      } catch (error) {
        if (error instanceof AssertionError) {
          throw error;
        }
        this.skip(); // skip test if coingecko fails to return price
      }
    });
  });

  describe("RamsesLPAggregatorTest", () => {
    it("Ensures lp price stays the same after huge swap", async () => {
      const priceBefore = (await token0tokenLPAggregator.latestRoundData())[1];

      const balanceOfToken1Before = await TOKEN1.balanceOf(deployments.owner.address);
      const ramsesRouter = await ethers.getContractAt("IVelodromeRouter", chainTestData.ramsesRouter);

      // ~ 100k$ swap
      const swapAmount = units(100_000, decimals0);
      await getAccountToken(swapAmount, deployments.owner.address, TOKEN0.address, chainTestData.token0Slot);

      await TOKEN0.approve(ramsesRouter.address, swapAmount);

      const routes = {
        from: TOKEN0.address,
        to: TOKEN1.address,
        stable: chainTestData.token0token1IsStable,
      };
      await ramsesRouter.swapExactTokensForTokens(
        swapAmount,
        0,
        [routes],
        deployments.owner.address,
        ethers.constants.MaxUint256,
      );

      const balanceOfToken1AfterFirstSwap = await TOKEN1.balanceOf(deployments.owner.address);
      expect(balanceOfToken1AfterFirstSwap).to.gt(balanceOfToken1Before);

      const priceAfter = (await token0tokenLPAggregator.latestRoundData())[1];

      expect(priceBefore).to.be.closeTo(priceAfter, priceAfter.div(10_000)); // 0.01% diff
    });
  });

  describe("RamsesXRamContractGuard", () => {
    before(async () => {
      const depositTx = iVelodromeGauge.encodeFunctionData("deposit", [lpAmount, 0]);
      await poolLogicProxy.connect(manager).execTransaction(RAMSES_GAUGE.address, depositTx);

      await deployments.assetHandler.setChainlinkTimeout(86400 * 180); // 180 days expiry
      await ethers.provider.send("evm_increaseTime", [3600 * 24 * 7]); // 3 days
      await ethers.provider.send("evm_mine", []);
    });

    it("should be able to create and exit vest", async () => {
      await poolLogicProxy
        .connect(manager)
        .execTransaction(
          RAMSES_GAUGE.address,
          iVelodromeGauge.encodeFunctionData("getReward", [poolLogicProxy.address, [RAM.address, xoRAM.address]]),
        );

      const ramBalanceAfterClaim = await RAM.balanceOf(poolLogicProxy.address);
      const balanceVested = await xoRAM.balanceOf(poolLogicProxy.address);

      await poolLogicProxy
        .connect(manager)
        .execTransaction(xoRAM.address, iXRam.encodeFunctionData("createVest", [balanceVested]));

      expect(await xoRAM.balanceOf(poolLogicProxy.address)).to.equal(0);

      expect(
        await (await ethers.getContractAt("IXRam", xoRAM.address)).usersTotalVests(poolLogicProxy.address),
      ).to.equal(1);

      await ethers.provider.send("evm_increaseTime", [3600 * 24 * 90]); // 90 days
      await ethers.provider.send("evm_mine", []);

      await poolLogicProxy
        .connect(manager)
        .execTransaction(xoRAM.address, iXRam.encodeFunctionData("exitVest", [0, false]));

      // Ensure full amount of RAM is received
      expect(await RAM.balanceOf(poolLogicProxy.address)).to.equal(ramBalanceAfterClaim.add(balanceVested));
    });
  });
});
