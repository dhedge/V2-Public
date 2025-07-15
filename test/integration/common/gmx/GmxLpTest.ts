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
  SlippageAccumulator,
  GmxExchangeRouterContractGuard,
} from "../../../../types";
import { deployGmxInfrastructure } from "./gmxDeploymentHelpers";
import { getAccountToken } from "../../utils/getAccountTokens";
import { expect } from "chai";
import {
  deduplicateTestTokenByAddress,
  executeOrder,
  GMX_ORACLE_LOOKUP_TYPE_PYTH_LIB,
  IGmxTestsParams,
} from "./gmxTestHelpers";
import { getEstimateDepositAmountOut, getEstimateWithdrawAmountOut } from "./utils";
import { units } from "../../../testHelpers";
import { updatePythPriceFeed } from "../../utils/pyth";

export type GmxDepositParams = {
  uiFeeReceiver?: string;
  depositVault?: string;
  receiver?: string;
  slippage?: number;
};

export type GmxWithdrawalParams = {
  withdrawalVault?: string;
  receiver?: string;
  amount: BigNumber;
  slippage?: number;
};

export const launchGmxLpTests = (testParams: IGmxTestsParams) => {
  let deployments: IBackboneDeployments;
  let logicOwner: SignerWithAddress;
  let whitelistedPoolLogic: PoolLogic;
  let whitelistedManagerLogic: PoolManagerLogic;
  let gmxExchangeRouterContractGuard: GmxExchangeRouterContractGuard;

  const iERC20 = new ethers.utils.Interface(IERC20__factory.abi);
  const iGmxExchangeRouter = new ethers.utils.Interface(IGmxExchangeRouter__factory.abi);

  const DUMMY_ADDRESS = ethers.Wallet.createRandom().address;

  let manager: SignerWithAddress;
  let slippageAccumulator: SlippageAccumulator;

  let token: IERC20;
  let beforeBeforeSnap: string;
  let beforeSnap1: string;
  let beforeSnap2: string;
  const SLIPPAGE_SET = 0.5;

  // utils.beforeAfterReset(beforeEach, afterEach);
  // utils.beforeAfterReset(before, after);

  before(async () => {
    beforeBeforeSnap = await utils.evmTakeSnap();
    deployments = await deployBackboneContracts(testParams);
    logicOwner = deployments.owner;
    manager = deployments.manager;

    const gmxInfrastucture = await deployGmxInfrastructure(deployments, testParams);

    whitelistedPoolLogic = gmxInfrastucture.whitelistedPool.poolLogicProxy;
    whitelistedManagerLogic = gmxInfrastucture.whitelistedPool.poolManagerLogicProxy;
    gmxExchangeRouterContractGuard = gmxInfrastucture.gmxExchangeRouterContractGuard;
    slippageAccumulator = deployments.slippageAccumulator;

    const testAssets = deduplicateTestTokenByAddress([
      testParams.longCollateral,
      testParams.shortCollateral,
      testParams.gasToken,
    ]);
    await Promise.all(
      testAssets.map(async (oneAsset) => {
        await getAccountToken(oneAsset.amount.mul(4), logicOwner.address, oneAsset.address, oneAsset.balanceOfSlot);
        token = await ethers.getContractAt("IERC20Extended", oneAsset.address);
        await token.approve(whitelistedPoolLogic.address, ethers.constants.MaxUint256);
        await whitelistedPoolLogic.deposit(oneAsset.address, oneAsset.amount.mul(4));
        const approveABI = iERC20.encodeFunctionData("approve", [
          testParams.approvalRouter,
          ethers.constants.MaxUint256,
        ]);
        await whitelistedPoolLogic.connect(manager).execTransaction(oneAsset.address, approveABI);
      }),
    );
    const approveABI = iERC20.encodeFunctionData("approve", [testParams.approvalRouter, ethers.constants.MaxUint256]);
    await whitelistedPoolLogic.connect(manager).execTransaction(testParams.market, approveABI);
    beforeSnap1 = await utils.evmTakeSnap();
    beforeSnap2 = await utils.evmTakeSnap();
  });

  after(async () => {
    await utils.evmRestoreSnap(beforeBeforeSnap);
  });

  //reusable functions
  const createDepositOrder = async (params: GmxDepositParams) => {
    for (const onePythAsset of testParams.vitrualTokenOracleSettings ?? []) {
      if (onePythAsset.oracleLookupType === GMX_ORACLE_LOOKUP_TYPE_PYTH_LIB)
        await updatePythPriceFeed(
          testParams.pythOracleContract,
          onePythAsset.pythOracleData.priceId.toString(),
          logicOwner,
        );
    }
    const sendGasTokensABI = iGmxExchangeRouter.encodeFunctionData("sendTokens", [
      testParams.gasToken.address,
      params.depositVault ?? testParams.depositVault,
      testParams.gasToken.amount,
    ]);

    const sendLongTokensABI = iGmxExchangeRouter.encodeFunctionData("sendTokens", [
      testParams.longCollateral.address,
      testParams.depositVault,
      testParams.longCollateral.amount.div(8),
    ]);

    const sendShortTokensABI = iGmxExchangeRouter.encodeFunctionData("sendTokens", [
      testParams.shortCollateral.address,
      testParams.depositVault,
      testParams.shortCollateral.amount.div(8),
    ]);

    // use the reader function getDepositAmountOut to estimate
    const { adjustMintAmountOut } = await getEstimateDepositAmountOut(testParams, {
      longTokenAmount: testParams.longCollateral.amount.div(8),
      shortTokenAmount: testParams.shortCollateral.amount.div(8),
      isToLog: true,
      slippage: !!params.slippage ? params.slippage : SLIPPAGE_SET,
    });

    const createDepositParams = {
      receiver: params.receiver ?? whitelistedPoolLogic.address,
      callbackContract: gmxExchangeRouterContractGuard.address,
      uiFeeReceiver: params.uiFeeReceiver ?? testParams.uiFeeReceiver,
      market: testParams.market,
      executionFee: testParams.gasToken.amount,
      callbackGasLimit: units(3, 6),
      minMarketTokens: adjustMintAmountOut,
      longTokenSwapPath: [],
      shortTokenSwapPath: [],
      shouldUnwrapNativeToken: false,
      initialLongToken: testParams.longCollateral.address,
      initialShortToken: testParams.shortCollateral.address,
    };

    // Encode the function data
    const createDepositABI = iGmxExchangeRouter.encodeFunctionData("createDeposit", [createDepositParams]);

    const multicallTxs = [sendGasTokensABI, sendLongTokensABI, sendShortTokensABI, createDepositABI];

    await whitelistedPoolLogic
      .connect(manager)
      .execTransaction(testParams.exchangeRouter, iGmxExchangeRouter.encodeFunctionData("multicall", [multicallTxs]));
  };

  const createWithdrawalOrder = async (params: GmxWithdrawalParams) => {
    const sendGasTokensABI = iGmxExchangeRouter.encodeFunctionData("sendTokens", [
      testParams.gasToken.address,
      params.withdrawalVault ?? testParams.withdrawalVault,
      testParams.gasToken.amount,
    ]);

    const sendMarketTokensABI = iGmxExchangeRouter.encodeFunctionData("sendTokens", [
      testParams.market,
      testParams.withdrawalVault,
      params.amount,
    ]);

    // use the reader function getDepositAmountOut to estimate
    const { adjustLongTokenAmountOut, adjustShortTokenAmountOut } = await getEstimateWithdrawAmountOut(testParams, {
      marketTokenAmount: params.amount,
      isToLog: true,
      slippage: !!params.slippage ? params.slippage : SLIPPAGE_SET,
    });

    const createWithdrawalParams = {
      receiver: params.receiver ?? whitelistedPoolLogic.address,
      callbackContract: gmxExchangeRouterContractGuard.address,
      uiFeeReceiver: testParams.uiFeeReceiver,
      market: testParams.market,
      executionFee: testParams.gasToken.amount,
      callbackGasLimit: units(3, 6),
      minLongTokenAmount: adjustLongTokenAmountOut,
      minShortTokenAmount: adjustShortTokenAmountOut,
      longTokenSwapPath: [],
      shortTokenSwapPath: [],
      shouldUnwrapNativeToken: false,
    };

    // Encode the function data
    const createWithdrawalABI = iGmxExchangeRouter.encodeFunctionData("createWithdrawal", [createWithdrawalParams]);

    const multicallTxs = [sendGasTokensABI, sendMarketTokensABI, createWithdrawalABI];

    await whitelistedPoolLogic
      .connect(manager)
      .execTransaction(testParams.exchangeRouter, iGmxExchangeRouter.encodeFunctionData("multicall", [multicallTxs]));
  };

  describe("Lp Deposit Checks", () => {
    it("Can't provide Lp if market is not enabled", async () => {
      await whitelistedManagerLogic.connect(manager).changeAssets([], [testParams.market]);
      await expect(createDepositOrder({})).to.revertedWith("unsupported market");
    });
    it("Can't provide lp if receiver is not pool", async () => {
      await whitelistedManagerLogic.connect(manager).changeAssets(
        [
          {
            asset: testParams.market,
            isDeposit: false,
          },
        ],
        [],
      );
      await expect(createDepositOrder({ receiver: DUMMY_ADDRESS })).to.revertedWith("receiver not pool logic");
    });
    it("Can't provide lp with invalid deposit vault", async () => {
      await expect(createDepositOrder({ depositVault: DUMMY_ADDRESS })).to.revertedWith("invalid receiver");
    });
    it("Can't provide lp if slippage is too high", async () => {
      // 1.6% slippage
      await expect(createDepositOrder({ slippage: 1.6 })).to.revertedWith("high slippage");
    });
    it("Can provide Lp to market", async () => {
      await utils.evmRestoreSnap(beforeSnap1);
      const totalFundValueBefore = await whitelistedManagerLogic.totalFundValue();
      const slippageAccBefore = await slippageAccumulator.getCumulativeSlippageImpact(whitelistedManagerLogic.address);
      await createDepositOrder({});
      const totalFundValueAfterDepositOrder = await whitelistedManagerLogic.totalFundValue();
      expect(totalFundValueAfterDepositOrder).to.be.closeTo(
        totalFundValueBefore,
        totalFundValueBefore.div(10_000), // 0.01%
      );
      await executeOrder({
        tokens: [testParams.longCollateral.address, testParams.shortCollateral.address],
        account: whitelistedPoolLogic.address,
        testParams,
        type: "DEPOSIT",
      });

      const slippageAccAfter = await slippageAccumulator.getCumulativeSlippageImpact(whitelistedManagerLogic.address);
      console.log("slippageAccBefore", slippageAccBefore);
      console.log("slippageAccAfter", slippageAccAfter);
      expect(slippageAccAfter).to.be.gte(slippageAccBefore); // can be 0 if positive slippage
      expect(slippageAccAfter.sub(slippageAccBefore.sub(3))).to.be.lt(SLIPPAGE_SET * 10000);
      const marketToken = await ethers.getContractAt("IERC20Extended", testParams.market);
      const marketTokenBalance = await marketToken.balanceOf(whitelistedPoolLogic.address);
      expect(marketTokenBalance).to.be.gt(0);
      const totalFundValueAfterDepositOrderExecution = await whitelistedManagerLogic.totalFundValue();
      expect(totalFundValueAfterDepositOrder).to.be.closeTo(
        totalFundValueAfterDepositOrderExecution,
        totalFundValueAfterDepositOrderExecution.div(100), // 1%
      );
    });
  });

  describe("Lp Withdrawal Checks", () => {
    before(async () => {
      await utils.evmRestoreSnap(beforeSnap2, 5);
    });

    it("Can withdraw lp from market", async () => {
      await createDepositOrder({});
      await executeOrder({
        tokens: [testParams.longCollateral.address, testParams.shortCollateral.address],
        account: whitelistedPoolLogic.address,
        testParams,
        type: "DEPOSIT",
      });
      const marketToken = await ethers.getContractAt("IERC20Extended", testParams.market);
      const marketTokenBalance = await marketToken.balanceOf(whitelistedPoolLogic.address);
      const totalFundValueBeforeWithdrawalOrder = await whitelistedManagerLogic.totalFundValue();
      const slippageAccBefore = await slippageAccumulator.getCumulativeSlippageImpact(whitelistedManagerLogic.address);
      await createWithdrawalOrder({ amount: marketTokenBalance });
      const totalFundValueAfterWithdrawalOrder = await whitelistedManagerLogic.totalFundValue();
      expect(totalFundValueBeforeWithdrawalOrder).to.be.closeTo(
        totalFundValueAfterWithdrawalOrder,
        totalFundValueAfterWithdrawalOrder.div(10_000), // 0.01%
      );
      await executeOrder({
        tokens: [testParams.longCollateral.address, testParams.shortCollateral.address],
        account: whitelistedPoolLogic.address,
        testParams,
        type: "WITHDRAWAL",
      });
      const slippageAccAfter = await slippageAccumulator.getCumulativeSlippageImpact(whitelistedManagerLogic.address);
      console.log("slippageAccBefore", slippageAccBefore);
      console.log("slippageAccAfter", slippageAccAfter);
      expect(slippageAccAfter).to.be.gte(slippageAccBefore.sub(3)); // can be 0 if positive slippage
      expect(slippageAccAfter.sub(slippageAccBefore)).to.be.lt(SLIPPAGE_SET * 10000);
      const totalFundValueAfterWithdrawalOrderExecution = await whitelistedManagerLogic.totalFundValue();
      expect(await marketToken.balanceOf(whitelistedPoolLogic.address)).to.be.eq(0);
      expect(totalFundValueAfterWithdrawalOrder).to.be.closeTo(
        totalFundValueAfterWithdrawalOrderExecution,
        totalFundValueAfterWithdrawalOrderExecution.div(100), // 1%
      );
    });
    describe("tests that can't withdraw", async () => {
      before(async () => {
        await createDepositOrder({});
        await executeOrder({
          tokens: [testParams.longCollateral.address, testParams.shortCollateral.address],
          account: whitelistedPoolLogic.address,
          testParams,
          type: "DEPOSIT",
        });
      });

      utils.beforeAfterReset(beforeEach, afterEach);

      it("Can't withdraw if withdrawal asset is not enabled", async () => {
        await getAccountToken(
          BigNumber.from(0),
          whitelistedPoolLogic.address,
          testParams.longCollateral.address,
          testParams.longCollateral.balanceOfSlot,
        );
        await whitelistedManagerLogic.connect(manager).changeAssets([], [testParams.longCollateral.address]);
        const marketToken = await ethers.getContractAt("IERC20Extended", testParams.market);
        const amount = await marketToken.balanceOf(whitelistedPoolLogic.address);
        await expect(createWithdrawalOrder({ amount })).to.revertedWith("unsupported withdrawal asset");
      });
      it("Can't withdraw if receiver is not pool", async () => {
        const marketToken = await ethers.getContractAt("IERC20Extended", testParams.market);
        const amount = await marketToken.balanceOf(whitelistedPoolLogic.address);
        await expect(createWithdrawalOrder({ amount, receiver: DUMMY_ADDRESS })).to.revertedWith(
          "receiver not pool logic",
        );
      });
      it("Can't withdraw with invalid withdrawal vault", async () => {
        const marketToken = await ethers.getContractAt("IERC20Extended", testParams.market);
        const amount = await marketToken.balanceOf(whitelistedPoolLogic.address);
        await expect(createWithdrawalOrder({ amount, withdrawalVault: DUMMY_ADDRESS })).to.revertedWith(
          "invalid receiver",
        );
      });
      it("Can't withdraw if slippage is too high", async () => {
        const marketToken = await ethers.getContractAt("IERC20Extended", testParams.market);
        const amount = await marketToken.balanceOf(whitelistedPoolLogic.address);
        await expect(createWithdrawalOrder({ amount, receiver: DUMMY_ADDRESS })).to.revertedWith(
          "receiver not pool logic",
        );
        // 1.6% slippage
        await expect(createWithdrawalOrder({ amount, slippage: 1.6 })).to.revertedWith("high slippage");
      });
    });
  });
};
