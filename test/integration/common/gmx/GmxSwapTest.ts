import { ethers } from "hardhat";
import { BigNumber } from "ethers";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";

import { IBackboneDeployments, deployBackboneContracts } from "../../utils/deployContracts/deployBackboneContracts";
import { utils } from "../../utils/utils";

import {
  PoolLogic,
  IERC20,
  IGmxExchangeRouter__factory,
  IERC20__factory,
  PoolManagerLogic,
  GmxExchangeRouterContractGuard,
} from "../../../../types";
import { deployGmxInfrastructure } from "./gmxDeploymentHelpers";
import { getAccountToken } from "../../utils/getAccountTokens";
import { expect } from "chai";
import {
  deduplicateTestTokenByAddress,
  executeOrder,
  GmxTestTokenAssetInfo,
  IGmxTestsParams,
  selectOppositeCollateralToken,
  selectTestTokenByAddress,
} from "./gmxTestHelpers";
import { getMinAmountOut } from "../../utils/getMinAmountOut";
import { units } from "../../../testHelpers";

export type GmxSwapOrderParams = {
  from: string;
  swapPath: string[];
  amountIn: BigNumber;
  minOutputAmount: BigNumber;
};

export const launchGmxSwapTests = (testParams: IGmxTestsParams) => {
  let deployments: IBackboneDeployments;
  let logicOwner: SignerWithAddress;
  let whitelistedPoolLogic: PoolLogic;
  let whitelistedManagerLogic: PoolManagerLogic;
  let gmxExchangeRouterContractGuard: GmxExchangeRouterContractGuard;

  const iERC20 = new ethers.utils.Interface(IERC20__factory.abi);
  const iGmxExchangeRouter = new ethers.utils.Interface(IGmxExchangeRouter__factory.abi);

  let manager: SignerWithAddress;

  let collateralToken: IERC20;
  let gasToken: IERC20;

  let token: IERC20;

  let perpCollateral: GmxTestTokenAssetInfo;

  utils.beforeAfterReset(beforeEach, afterEach);
  utils.beforeAfterReset(before, after);

  before(async () => {
    deployments = await deployBackboneContracts(testParams);
    logicOwner = deployments.owner;
    manager = deployments.manager;

    const gmxInfrastucture = await deployGmxInfrastructure(deployments, testParams);

    whitelistedPoolLogic = gmxInfrastucture.whitelistedPool.poolLogicProxy;
    whitelistedManagerLogic = gmxInfrastucture.whitelistedPool.poolManagerLogicProxy;
    gmxExchangeRouterContractGuard = gmxInfrastucture.gmxExchangeRouterContractGuard;

    const testAssets = deduplicateTestTokenByAddress([
      testParams.longCollateral,
      testParams.shortCollateral,
      testParams.gasToken,
    ]);
    await Promise.all(
      testAssets.map(async (oneAsset) => {
        await getAccountToken(oneAsset.amount.mul(2), logicOwner.address, oneAsset.address, oneAsset.balanceOfSlot);
        token = await ethers.getContractAt("IERC20Extended", oneAsset.address);
        await token.approve(whitelistedPoolLogic.address, ethers.constants.MaxUint256);
        await whitelistedPoolLogic.deposit(oneAsset.address, oneAsset.amount.mul(2));
        const approveABI = iERC20.encodeFunctionData("approve", [
          testParams.approvalRouter,
          ethers.constants.MaxUint256,
        ]);
        await whitelistedPoolLogic.connect(manager).execTransaction(oneAsset.address, approveABI);
      }),
    );
    perpCollateral = selectTestTokenByAddress({
      assets: deduplicateTestTokenByAddress([
        testParams.longCollateral,
        testParams.shortCollateral,
        testParams.gasToken,
      ]),
      assetAddress: testParams.vaultCollateralAsset,
    });
    collateralToken = await ethers.getContractAt("IERC20Extended", perpCollateral.address);
    gasToken = await ethers.getContractAt("IERC20Extended", testParams.gasToken.address);
  });

  //reusable functions
  const createSwapOrder = async (params: GmxSwapOrderParams) => {
    const sendGasTokensABI = iGmxExchangeRouter.encodeFunctionData("sendTokens", [
      testParams.gasToken.address,
      testParams.orderVault,
      testParams.gasToken.amount.div(2),
    ]);

    const sendCollateralTokensABI = iGmxExchangeRouter.encodeFunctionData("sendTokens", [
      params.from,
      testParams.orderVault,
      params.amountIn,
    ]);

    const addresses = {
      receiver: whitelistedPoolLogic.address,
      cancellationReceiver: ethers.constants.AddressZero,
      callbackContract: gmxExchangeRouterContractGuard.address,
      uiFeeReceiver: testParams.uiFeeReceiver,
      market: ethers.constants.AddressZero,
      initialCollateralToken: params.from,
      swapPath: params.swapPath,
    };

    const numbers = {
      sizeDeltaUsd: ethers.constants.Zero,
      initialCollateralDeltaAmount: ethers.constants.Zero,
      triggerPrice: ethers.constants.Zero,
      acceptablePrice: ethers.constants.Zero,
      executionFee: testParams.gasToken.amount.div(2),
      callbackGasLimit: units(3, 6),
      minOutputAmount: params.minOutputAmount,
      validFromTime: ethers.constants.Zero,
    };

    const createOrderParams = {
      addresses: addresses,
      numbers: numbers,
      orderType: 0,
      decreasePositionSwapType: 0,
      isLong: false,
      shouldUnwrapNativeToken: false,
      autoCancel: false, // Set true to enable auto-cancellation
      referralCode: ethers.utils.formatBytes32String(""), // Set a referral code if any
    };

    // Encode the function data
    const createOrderABI = iGmxExchangeRouter.encodeFunctionData("createOrder", [createOrderParams]);

    const multicallTxs = [sendGasTokensABI, sendCollateralTokensABI, createOrderABI];

    await whitelistedPoolLogic
      .connect(manager)
      .execTransaction(testParams.exchangeRouter, iGmxExchangeRouter.encodeFunctionData("multicall", [multicallTxs]));
  };

  describe("Swap Checks", () => {
    it("Can't swap if swap path more than one market", async () => {
      const swapParams = {
        from: perpCollateral.address,
        swapPath: [testParams.market, testParams.market],
        amountIn: perpCollateral.amount.div(2),
        minOutputAmount: ethers.constants.Zero,
      };
      await expect(createSwapOrder(swapParams)).to.revertedWith("invalid swap path");
    });

    it("Can't swap if market is not enabled", async () => {
      await whitelistedManagerLogic.connect(manager).changeAssets([], [testParams.market]);

      const swapParams: GmxSwapOrderParams = {
        from: perpCollateral.address,
        swapPath: [testParams.market],
        amountIn: perpCollateral.amount.div(2),
        minOutputAmount: ethers.constants.Zero,
      };
      await expect(createSwapOrder(swapParams)).to.revertedWith("unsupported market");

      await whitelistedManagerLogic.connect(manager).changeAssets(
        [
          {
            asset: testParams.market,
            isDeposit: false,
          },
        ],
        [],
      );
    });
    it("Can swap collateral", async () => {
      const tokenIn = perpCollateral.address;
      const tokenOut = selectOppositeCollateralToken({
        testParams,
      }).address;
      const tokenInAmount = perpCollateral.amount.div(2);

      const estimatedMinTokenOut1Percent = await getMinAmountOut(
        deployments.assetHandler,
        tokenInAmount,
        tokenIn,
        tokenOut,
        1, // get 1% of tokenInValue
      );
      // 99% out; 1% slippage
      const estimatedMinTokenOut = estimatedMinTokenOut1Percent.mul(100).sub(estimatedMinTokenOut1Percent);

      console.log("estimatedMinTokenOut", estimatedMinTokenOut.toString());
      const swapParams: GmxSwapOrderParams = {
        from: perpCollateral.address,
        swapPath: [testParams.market],
        amountIn: tokenInAmount,
        minOutputAmount: estimatedMinTokenOut,
      };
      const totalFundValueBefore = await whitelistedManagerLogic.totalFundValue();
      const collateralBalBefore = await collateralToken.balanceOf(whitelistedPoolLogic.address);

      const slippageAccBefore = await deployments.slippageAccumulator.getCumulativeSlippageImpact(
        whitelistedManagerLogic.address,
      );
      await createSwapOrder(swapParams);
      const totalFundAfterOrderCreation = await whitelistedManagerLogic.totalFundValue();
      expect(totalFundAfterOrderCreation.eq(totalFundValueBefore));
      await executeOrder({
        tokens: [tokenIn, tokenOut],
        account: whitelistedPoolLogic.address,
        testParams,
        type: "ORDER",
      });
      const collateralBalAfter = await collateralToken.balanceOf(whitelistedPoolLogic.address);
      expect(collateralBalBefore.sub(collateralBalAfter)).eq(tokenInAmount);
      expect(await gasToken.balanceOf(whitelistedPoolLogic.address)).gt(testParams.gasToken.amount);
      const slippageAccAfter = await deployments.slippageAccumulator.getCumulativeSlippageImpact(
        whitelistedManagerLogic.address,
      );
      console.log("slippageAccBefore", slippageAccBefore);
      console.log("slippageAccAfter", slippageAccAfter);
      expect(slippageAccAfter).to.be.gte(slippageAccBefore); // can be 0 if positive slippage
      expect(slippageAccAfter.sub(slippageAccBefore)).to.be.lt(1 * 10000); // 1% slippage
      const totalFundValueAfterOrderExecution = await whitelistedManagerLogic.totalFundValue();
      expect(totalFundValueAfterOrderExecution).to.be.closeTo(
        totalFundValueBefore,
        totalFundValueBefore.div(100), // 1% slippage
      );
    });

    it("Can't swap collateral if minOutputAmount is low (high slippage)", async () => {
      const tokenIn = perpCollateral.address;
      const tokenOut = selectOppositeCollateralToken({
        testParams,
      }).address;
      const tokenInAmount = perpCollateral.amount.div(2);

      // 0.1%
      const estimatedMinTokenOutPoint1Percent = (
        await getMinAmountOut(
          deployments.assetHandler,
          tokenInAmount,
          tokenIn,
          tokenOut,
          1, // get 1% of tokenInValue
        )
      ).div(10);
      // 98.3% out; 1.7% slippage
      const estimatedMinTokenOut = estimatedMinTokenOutPoint1Percent.mul(983);

      const swapParams1: GmxSwapOrderParams = {
        from: perpCollateral.address,
        swapPath: [testParams.market],
        amountIn: perpCollateral.amount.div(2),
        minOutputAmount: estimatedMinTokenOut,
      };

      await expect(createSwapOrder(swapParams1)).to.revertedWith("high slippage");

      const swapParams2: GmxSwapOrderParams = {
        from: perpCollateral.address,
        swapPath: [testParams.market],
        amountIn: perpCollateral.amount.div(2),
        minOutputAmount: ethers.constants.Zero,
      };
      await expect(createSwapOrder(swapParams2)).to.revertedWith("high slippage");
    });
  });
};
