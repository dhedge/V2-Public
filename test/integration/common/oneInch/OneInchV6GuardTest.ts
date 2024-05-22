import { expect } from "chai";
import { BigNumberish } from "ethers";
import { ethers } from "hardhat";
import {
  IBackboneDeployments,
  IBackboneDeploymentsParams,
  IERC20Path,
  deployBackboneContracts,
  iERC20,
} from "../../utils/deployContracts/deployBackboneContracts";
import { ChainIds, utils } from "../../utils/utils";
import { createFund } from "../../utils/createFund";
import { getAccountToken } from "../../utils/getAccountTokens";
import { IERC20, PoolLogic, PoolManagerLogic, OneInchV6Guard, IAggregationRouterV6__factory } from "../../../../types";
import { units } from "../../../testHelpers";
import { getOneInchSwapTransaction } from "../../utils/oneInchHelpers";
import { assetSetting } from "../../utils/deployContracts/getChainAssets";
import { AssetType } from "../../../../deployment/upgrade/jobs/assetsJob";

const tokenFromAmount = units(1_000, 6);

const IAggregationRouterV6 = new ethers.utils.Interface(IAggregationRouterV6__factory.abi);

type ITestParams = IBackboneDeploymentsParams & {
  chainId: ChainIds;
  aggregationRouterV6: string;
  assetsBalanceOfSlot: {
    usdc: number;
    dai: number;
    weth: number;
  };
  assetsOptimism?: {
    snx: {
      address: string;
      priceFeed: string;
      proxy: string;
      balanceOfSlot: number;
    };
    susd: {
      address: string;
      priceFeed: string;
    };
  };
};

export const runOneInchV6GuardTest = async (testParams: ITestParams) => {
  describe("OneInchV6Guard Test", () => {
    let deployments: IBackboneDeployments;
    let v6Guard: OneInchV6Guard;
    let poolLogicProxy: PoolLogic;
    let poolManagerLogicProxy: PoolManagerLogic;
    let USDC: IERC20, DAI: IERC20, WETH: IERC20;

    utils.beforeAfterReset(beforeEach, afterEach);
    utils.beforeAfterReset(before, after);

    before(async () => {
      deployments = await deployBackboneContracts(testParams);
      const OneInchV6Guard = await ethers.getContractFactory("OneInchV6Guard");
      const oneInchV6Guard = await OneInchV6Guard.deploy(deployments.slippageAccumulator.address);
      await oneInchV6Guard.deployed();
      v6Guard = oneInchV6Guard;

      await deployments.governance.setContractGuard(testParams.aggregationRouterV6, oneInchV6Guard.address);

      USDC = deployments.assets.USDC;
      DAI = deployments.assets.DAI;
      WETH = deployments.assets.WETH;

      const proxies = await createFund(deployments.poolFactory, deployments.owner, deployments.manager, [
        {
          asset: USDC.address,
          isDeposit: true,
        },
        {
          asset: DAI.address,
          isDeposit: true,
        },
        {
          asset: WETH.address,
          isDeposit: true,
        },
      ]);
      poolLogicProxy = proxies.poolLogicProxy;
      poolManagerLogicProxy = proxies.poolManagerLogicProxy;

      await getAccountToken(
        tokenFromAmount,
        deployments.owner.address,
        USDC.address,
        testParams.assetsBalanceOfSlot.usdc,
      );

      await USDC.approve(poolLogicProxy.address, tokenFromAmount);
      await poolLogicProxy.deposit(USDC.address, tokenFromAmount);

      // Technically disables slippage protection
      await deployments.slippageAccumulator.setMaxCumulativeSlippage(1000e4);
    });

    const approveV6Router = async (poolLogic: PoolLogic, token: string, amount: BigNumberish) => {
      await poolLogic
        .connect(deployments.manager)
        .execTransaction(token, iERC20.encodeFunctionData("approve", [testParams.aggregationRouterV6, amount]));
    };

    const disableTokenInThePool = async (tokenAddress: string, poolManagerlogic = poolManagerLogicProxy) => {
      await poolManagerlogic.connect(deployments.manager).changeAssets([], [tokenAddress]);
    };

    it("should revert if txGuard caller is not pool", async () => {
      await expect(
        v6Guard.txGuard(poolManagerLogicProxy.address, testParams.aggregationRouterV6, []),
      ).to.be.revertedWith("not pool logic");
    });

    describe("swap", () => {
      const isUsingSwapMethod = (txData: string): boolean => {
        try {
          // Will throw if data doesn't match function "swap"
          IAggregationRouterV6.decodeFunctionData("swap", txData);
          return true;
        } catch {
          return false;
        }
      };

      it("should revert if destination token is not enabled", async () => {
        await disableTokenInThePool(DAI.address);

        const txData = await getOneInchSwapTransaction({
          src: USDC.address,
          dst: DAI.address,
          amount: tokenFromAmount,
          from: poolLogicProxy.address,
          receiver: poolLogicProxy.address,
          chainId: testParams.chainId,
          version: "6.0",
        });

        await expect(
          poolLogicProxy.connect(deployments.manager).execTransaction(testParams.aggregationRouterV6, txData),
        ).to.be.revertedWith("unsupported destination asset");
      });

      it("should revert if trying to unwrap", async () => {
        await utils.delay();

        const txData = await getOneInchSwapTransaction({
          src: WETH.address,
          dst: "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE",
          amount: tokenFromAmount,
          from: poolLogicProxy.address,
          receiver: poolLogicProxy.address,
          chainId: testParams.chainId,
          version: "6.0",
        });
        const swapUsed = isUsingSwapMethod(txData);
        const revertMessage = swapUsed ? "unsupported destination asset" : "WETH unwrap not supported";

        await expect(
          poolLogicProxy.connect(deployments.manager).execTransaction(testParams.aggregationRouterV6, txData),
        ).to.be.revertedWith(revertMessage);
      });

      it("should revert if destination receiver is not pool", async () => {
        await utils.delay();

        const txData = await getOneInchSwapTransaction({
          src: USDC.address,
          dst: DAI.address,
          amount: tokenFromAmount,
          from: poolLogicProxy.address,
          receiver: deployments.manager.address,
          chainId: testParams.chainId,
          version: "6.0",
        });
        const swapUsed = isUsingSwapMethod(txData);
        // If it's not "swap", it may be something of `unoswapTo` or similar which we simply don't support in the guard
        const revertMessage = swapUsed ? "recipient is not pool" : "invalid transaction";

        await expect(
          poolLogicProxy.connect(deployments.manager).execTransaction(testParams.aggregationRouterV6, txData),
        ).to.be.revertedWith(revertMessage);
      });

      it("should be able to swap", async () => {
        await utils.delay();

        const totalValueBefore = await poolManagerLogicProxy.totalFundValue();
        const tokenToBalanceBefore = await DAI.balanceOf(poolLogicProxy.address);
        expect(tokenToBalanceBefore).to.be.eq(0);
        const tokenFromBalanceBefore = await USDC.balanceOf(poolLogicProxy.address);
        expect(tokenFromBalanceBefore).to.be.gt(0);

        const src = USDC.address;
        const txData = await getOneInchSwapTransaction({
          src,
          dst: DAI.address,
          amount: tokenFromBalanceBefore,
          from: poolLogicProxy.address,
          receiver: poolLogicProxy.address,
          chainId: testParams.chainId,
          version: "6.0",
        });
        const swapUsed = isUsingSwapMethod(txData);

        await approveV6Router(poolLogicProxy, src, tokenFromBalanceBefore);

        await poolLogicProxy.connect(deployments.manager).execTransaction(testParams.aggregationRouterV6, txData);
        console.log(`Transaction data used "swap" method:`, swapUsed);

        const totalValueAfter = await poolManagerLogicProxy.totalFundValue();
        const tokenToBalanceAfter = await DAI.balanceOf(poolLogicProxy.address);
        const tokenFromBalanceAfter = await USDC.balanceOf(poolLogicProxy.address);
        expect(tokenToBalanceAfter).to.be.gt(0);
        expect(tokenFromBalanceAfter).to.be.eq(0);
        expect(totalValueBefore).to.be.closeTo(totalValueAfter, totalValueAfter.div(1_000)); // 0.1% tolerance
      });
    });

    const MIN_AMOUNT_OUT = "0"; // Same for all unoswapX tests

    const UNOSWAP = "unoswap";
    // Based on this transaction: https://optimistic.etherscan.io/tx/0xe74ee1cb1ad1f3cbd6231b4f2b6fa60c20c0de8b68ce0868f58edb0c9460ac03
    describe(UNOSWAP, () => {
      let unoswapTestPoolLogic: PoolLogic;
      let unoswapTestPoolManagerLogic: PoolManagerLogic;
      let SNX: IERC20, sUSD: IERC20;

      before(async function () {
        if (!testParams.assetsOptimism) {
          return this.skip();
        }

        SNX = <IERC20>await ethers.getContractAt(IERC20Path, testParams.assetsOptimism.snx.address);
        sUSD = <IERC20>await ethers.getContractAt(IERC20Path, testParams.assetsOptimism.susd.address);

        await deployments.assetHandler.addAssets([
          assetSetting(
            SNX.address,
            AssetType["Chainlink direct USD price feed with 8 decimals"],
            testParams.assetsOptimism.snx.priceFeed,
          ),
          assetSetting(
            sUSD.address,
            AssetType["Chainlink direct USD price feed with 8 decimals"],
            testParams.assetsOptimism.susd.priceFeed,
          ),
        ]);
        const proxies = await createFund(deployments.poolFactory, deployments.owner, deployments.manager, [
          {
            asset: SNX.address,
            isDeposit: true,
          },
          {
            asset: sUSD.address,
            isDeposit: true,
          },
        ]);
        unoswapTestPoolLogic = proxies.poolLogicProxy;
        unoswapTestPoolManagerLogic = proxies.poolManagerLogicProxy;

        const amount = units(10);

        await getAccountToken(
          amount,
          deployments.owner.address,
          testParams.assetsOptimism.snx.proxy,
          testParams.assetsOptimism.snx.balanceOfSlot,
        );

        await SNX.approve(unoswapTestPoolLogic.address, amount);
        await unoswapTestPoolLogic.deposit(SNX.address, amount);
      });

      it("should revert if destination token is not enabled", async () => {
        await disableTokenInThePool(sUSD.address, unoswapTestPoolManagerLogic);

        const txData = IAggregationRouterV6.encodeFunctionData(UNOSWAP, [
          "770732824917550708650077921396772781039761594804",
          "30000000000000000",
          "153430637128991182",
          "18318670367622288729119628488804091446149237509519701739095565606608741747389",
        ]);

        await expect(
          unoswapTestPoolLogic.connect(deployments.manager).execTransaction(testParams.aggregationRouterV6, txData),
        ).to.be.revertedWith("unsupported destination asset");
      });

      it("should be able to swap", async () => {
        const srcAmount = "30000000000000000";

        await approveV6Router(unoswapTestPoolLogic, SNX.address, srcAmount);

        const totalValueBefore = await unoswapTestPoolManagerLogic.totalFundValue();
        const tokenToBalanceBefore = await sUSD.balanceOf(unoswapTestPoolLogic.address);
        expect(tokenToBalanceBefore).to.be.eq(0);
        const tokenFromBalanceBefore = await SNX.balanceOf(unoswapTestPoolLogic.address);
        expect(tokenFromBalanceBefore).to.be.gte(srcAmount);

        const txData = IAggregationRouterV6.encodeFunctionData(UNOSWAP, [
          "770732824917550708650077921396772781039761594804",
          srcAmount,
          MIN_AMOUNT_OUT,
          "18318670367622288729119628488804091446149237509519701739095565606608741747389",
        ]);

        await unoswapTestPoolLogic.connect(deployments.manager).execTransaction(testParams.aggregationRouterV6, txData);

        const totalValueAfter = await unoswapTestPoolManagerLogic.totalFundValue();
        const tokenToBalanceAfter = await sUSD.balanceOf(unoswapTestPoolLogic.address);
        const tokenFromBalanceAfter = await SNX.balanceOf(unoswapTestPoolLogic.address);
        expect(tokenFromBalanceAfter).to.be.lt(tokenFromBalanceBefore);
        expect(tokenToBalanceAfter).to.be.gt(MIN_AMOUNT_OUT);
        expect(totalValueBefore).to.be.closeTo(totalValueAfter, totalValueBefore.div(1000)); // 0.1% tolerance
      });
    });

    const UNOSWAP2 = "unoswap2";
    // Based on this transaction: https://optimistic.etherscan.io/tx/0xbd263a4c7cbb877a5e527ea6ed95ae12c36b84049054f168f837582586a89bc8
    describe(UNOSWAP2, () => {
      let unoswap2TestPoolLogic: PoolLogic;
      let unoswap2TestPoolManagerLogic: PoolManagerLogic;
      let SNX: IERC20, sUSD: IERC20;

      before(async function () {
        if (!testParams.assetsOptimism) {
          return this.skip();
        }

        SNX = <IERC20>await ethers.getContractAt(IERC20Path, testParams.assetsOptimism.snx.address);
        sUSD = <IERC20>await ethers.getContractAt(IERC20Path, testParams.assetsOptimism.susd.address);

        await deployments.assetHandler.addAssets([
          assetSetting(
            SNX.address,
            AssetType["Chainlink direct USD price feed with 8 decimals"],
            testParams.assetsOptimism.snx.priceFeed,
          ),
          assetSetting(
            sUSD.address,
            AssetType["Chainlink direct USD price feed with 8 decimals"],
            testParams.assetsOptimism.susd.priceFeed,
          ),
        ]);
        const proxies = await createFund(deployments.poolFactory, deployments.owner, deployments.manager, [
          {
            asset: SNX.address,
            isDeposit: true,
          },
          {
            asset: sUSD.address,
            isDeposit: true,
          },
        ]);
        unoswap2TestPoolLogic = proxies.poolLogicProxy;
        unoswap2TestPoolManagerLogic = proxies.poolManagerLogicProxy;

        const amount = units(10);

        await getAccountToken(
          amount,
          deployments.owner.address,
          testParams.assetsOptimism.snx.proxy,
          testParams.assetsOptimism.snx.balanceOfSlot,
        );

        await SNX.approve(unoswap2TestPoolLogic.address, amount);
        await unoswap2TestPoolLogic.deposit(SNX.address, amount);
      });

      it("should revert if destination token is not enabled", async () => {
        await disableTokenInThePool(sUSD.address, unoswap2TestPoolManagerLogic);

        const txData = IAggregationRouterV6.encodeFunctionData(UNOSWAP2, [
          "770732824917550708650077921396772781039761594804",
          "74540133383346574",
          "318733799805373667",
          "18092513943330655534932966407627884106503102850964999170115231963902734527202",
          "14700167578956157622133035206939913372848946839765861875583565648636723101079",
        ]);

        await expect(
          unoswap2TestPoolLogic.connect(deployments.manager).execTransaction(testParams.aggregationRouterV6, txData),
        ).to.be.revertedWith("unsupported destination asset");
      });

      it("should be able to swap", async () => {
        const srcAmount = "74540133383346574";

        await approveV6Router(unoswap2TestPoolLogic, SNX.address, srcAmount);

        const totalValueBefore = await unoswap2TestPoolManagerLogic.totalFundValue();
        const tokenToBalanceBefore = await sUSD.balanceOf(unoswap2TestPoolLogic.address);
        expect(tokenToBalanceBefore).to.be.eq(0);
        const tokenFromBalanceBefore = await SNX.balanceOf(unoswap2TestPoolLogic.address);
        expect(tokenFromBalanceBefore).to.be.gte(srcAmount);

        const txData = IAggregationRouterV6.encodeFunctionData(UNOSWAP2, [
          "770732824917550708650077921396772781039761594804",
          srcAmount,
          MIN_AMOUNT_OUT,
          "18092513943330655534932966407627884106503102850964999170115231963902734527202",
          "14700167578956157622133035206939913372848946839765861875583565648636723101079",
        ]);

        await unoswap2TestPoolLogic
          .connect(deployments.manager)
          .execTransaction(testParams.aggregationRouterV6, txData);

        const totalValueAfter = await unoswap2TestPoolManagerLogic.totalFundValue();
        const tokenToBalanceAfter = await sUSD.balanceOf(unoswap2TestPoolLogic.address);
        const tokenFromBalanceAfter = await SNX.balanceOf(unoswap2TestPoolLogic.address);
        expect(tokenFromBalanceAfter).to.be.lt(tokenFromBalanceBefore);
        expect(tokenToBalanceAfter).to.be.gt(MIN_AMOUNT_OUT);
        expect(totalValueBefore).to.be.closeTo(totalValueAfter, totalValueBefore.div(1000)); // 0.1% tolerance
      });
    });

    const UNOSWAP3 = "unoswap3";
    // Based on this transaction: https://optimistic.etherscan.io/tx/0xbe70303fdc4cecf8a801ab6de6f3f8a6deafdbfe539fbf4ac452b337cdb1f2fb
    describe(UNOSWAP3, () => {
      let unoswap3TestPoolLogic: PoolLogic;
      let unoswap3TestPoolManagerLogic: PoolManagerLogic;
      let SNX: IERC20, sUSD: IERC20;

      before(async function () {
        if (!testParams.assetsOptimism) {
          return this.skip();
        }

        SNX = <IERC20>await ethers.getContractAt(IERC20Path, testParams.assetsOptimism.snx.address);
        sUSD = <IERC20>await ethers.getContractAt(IERC20Path, testParams.assetsOptimism.susd.address);

        await deployments.assetHandler.addAssets([
          assetSetting(
            SNX.address,
            AssetType["Chainlink direct USD price feed with 8 decimals"],
            testParams.assetsOptimism.snx.priceFeed,
          ),
          assetSetting(
            sUSD.address,
            AssetType["Chainlink direct USD price feed with 8 decimals"],
            testParams.assetsOptimism.susd.priceFeed,
          ),
        ]);
        const proxies = await createFund(deployments.poolFactory, deployments.owner, deployments.manager, [
          {
            asset: SNX.address,
            isDeposit: true,
          },
          {
            asset: sUSD.address,
            isDeposit: true,
          },
        ]);
        unoswap3TestPoolLogic = proxies.poolLogicProxy;
        unoswap3TestPoolManagerLogic = proxies.poolManagerLogicProxy;

        const amount = units(10);

        await getAccountToken(
          amount,
          deployments.owner.address,
          testParams.assetsOptimism.snx.proxy,
          testParams.assetsOptimism.snx.balanceOfSlot,
        );

        await SNX.approve(unoswap3TestPoolLogic.address, amount);
        await unoswap3TestPoolLogic.deposit(SNX.address, amount);
      });

      it("should revert if destination token is not enabled", async () => {
        await disableTokenInThePool(sUSD.address, unoswap3TestPoolManagerLogic);

        const txData = IAggregationRouterV6.encodeFunctionData(UNOSWAP3, [
          "770732824917550708650077921396772781039761594804",
          "908985336371968589",
          "4028356351536244620",
          "18092513943330655534932966407627884106503102850964999170115231963902734527202",
          "14700167578956157622133035207036579277432594969652305376452131855374071355840",
          "14474011154664524427946373126932182750819595237909269397439552822227304046777",
        ]);

        await expect(
          unoswap3TestPoolLogic.connect(deployments.manager).execTransaction(testParams.aggregationRouterV6, txData),
        ).to.be.revertedWith("unsupported destination asset");
      });

      it("should be able to swap", async () => {
        const srcAmount = "908985336371968589";

        await approveV6Router(unoswap3TestPoolLogic, SNX.address, srcAmount);

        const totalValueBefore = await unoswap3TestPoolManagerLogic.totalFundValue();
        const tokenToBalanceBefore = await sUSD.balanceOf(unoswap3TestPoolLogic.address);
        expect(tokenToBalanceBefore).to.be.eq(0);
        const tokenFromBalanceBefore = await SNX.balanceOf(unoswap3TestPoolLogic.address);
        expect(tokenFromBalanceBefore).to.be.gte(srcAmount);

        const txData = IAggregationRouterV6.encodeFunctionData(UNOSWAP3, [
          "770732824917550708650077921396772781039761594804",
          srcAmount,
          MIN_AMOUNT_OUT,
          "18092513943330655534932966407627884106503102850964999170115231963902734527202",
          "14700167578956157622133035207036579277432594969652305376452131855374071355840",
          "14474011154664524427946373126932182750819595237909269397439552822227304046777",
        ]);

        await unoswap3TestPoolLogic
          .connect(deployments.manager)
          .execTransaction(testParams.aggregationRouterV6, txData);

        const totalValueAfter = await unoswap3TestPoolManagerLogic.totalFundValue();
        const tokenToBalanceAfter = await sUSD.balanceOf(unoswap3TestPoolLogic.address);
        const tokenFromBalanceAfter = await SNX.balanceOf(unoswap3TestPoolLogic.address);
        expect(tokenFromBalanceAfter).to.be.lt(tokenFromBalanceBefore);
        expect(tokenToBalanceAfter).to.be.gt(MIN_AMOUNT_OUT);
        expect(totalValueBefore).to.be.closeTo(totalValueAfter, totalValueBefore.div(1000)); // 0.1% tolerance
      });
    });
  });
};
