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
import { assert, expect } from "chai";
import {
  deduplicateTestTokenByAddress,
  executeOrder,
  GMX_ORACLE_LOOKUP_TYPE_PYTH_LIB,
  GmxTestTokenAssetInfo,
  IGmxTestsParams,
  selectOppositeCollateralToken,
  selectTestTokenByAddress,
} from "./gmxTestHelpers";
import { units } from "../../../testHelpers";
import { after, before } from "mocha";
import { updatePythPriceFeed } from "../../utils/pyth";

export type GmxOrderParams = {
  uiFeeReceiver?: string;
  orderVault?: string;
  receiver?: string;
  collateralToken?: string;
  callbackContract?: string;
  onlySendTokens?: boolean;
  decreasePosition?: boolean;
  sizeDeltaUsd?: BigNumber;
  initialCollateralDeltaAmount?: BigNumber;
};

export const launchGmxPerpsTests = (testParams: IGmxTestsParams) => {
  let deployments: IBackboneDeployments;
  let logicOwner: SignerWithAddress;
  let whitelistedPoolLogic: PoolLogic;
  // let whitelistedManagerLogic: PoolManagerLogic;

  const iERC20 = new ethers.utils.Interface(IERC20__factory.abi);
  const iGmxExchangeRouter = new ethers.utils.Interface(IGmxExchangeRouter__factory.abi);

  const DUMMY_ADDRESS = ethers.Wallet.createRandom().address;

  let manager: SignerWithAddress;
  let whitelistedManagerLogic: PoolManagerLogic;

  let token: IERC20;

  let perpCollateral: GmxTestTokenAssetInfo;
  let gmxExchangeRouterContractGuard: GmxExchangeRouterContractGuard;
  let snap1;

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
    snap1 = await utils.evmTakeSnap();
  });

  //reusable functions
  const openOrder = async (params: GmxOrderParams) => {
    for (const onePythAsset of testParams.vitrualTokenOracleSettings ?? []) {
      if (onePythAsset.oracleLookupType === GMX_ORACLE_LOOKUP_TYPE_PYTH_LIB) {
        await updatePythPriceFeed(
          testParams.pythOracleContract,
          onePythAsset.pythOracleData.priceId.toString(),
          logicOwner,
        );
      }
    }

    const sendGasTokensABI = iGmxExchangeRouter.encodeFunctionData("sendTokens", [
      testParams.gasToken.address,
      params.orderVault ?? testParams.orderVault,
      testParams.gasToken.amount.div(2),
    ]);

    const sizeDeltaUsd = !!params.sizeDeltaUsd
      ? params.sizeDeltaUsd
      : params.decreasePosition
        ? testParams.sizeAmount.div(2)
        : testParams.sizeAmount;
    const initialCollateralDeltaAmount = !!params.initialCollateralDeltaAmount
      ? params.initialCollateralDeltaAmount
      : params.decreasePosition
        ? perpCollateral.amount.div(4)
        : perpCollateral.amount.div(2);

    // for increase position, 0 is ok here
    // initialCollateralDeltaAmount will be recorded by the amount sent in OrderVault after the createOrder call
    const initialCollateralDeltaAmountInNumbers = params.decreasePosition
      ? initialCollateralDeltaAmount
      : ethers.constants.Zero;

    const sendCollateralTokensABI = iGmxExchangeRouter.encodeFunctionData("sendTokens", [
      params.collateralToken ?? perpCollateral.address,
      params.orderVault ?? testParams.orderVault,
      initialCollateralDeltaAmount,
    ]);

    const addresses = {
      receiver: whitelistedPoolLogic.address,
      cancellationReceiver: ethers.constants.AddressZero,
      callbackContract: params.callbackContract ?? gmxExchangeRouterContractGuard.address,
      uiFeeReceiver: params.uiFeeReceiver ?? testParams.uiFeeReceiver,
      market: testParams.market,
      initialCollateralToken: params.collateralToken ?? perpCollateral.address,
      swapPath: [],
    };

    const numbers = {
      sizeDeltaUsd,
      initialCollateralDeltaAmount: initialCollateralDeltaAmountInNumbers,
      triggerPrice: ethers.constants.Zero,
      acceptablePrice: params.decreasePosition ? 0 : ethers.constants.MaxUint256, // for testing
      executionFee: testParams.gasToken.amount.div(2),
      callbackGasLimit: units(2, 6),
      minOutputAmount: ethers.constants.Zero,
      validFromTime: ethers.constants.Zero,
    };

    const createOrderParams = {
      addresses: addresses,
      numbers: numbers,
      orderType: params.decreasePosition ? 4 : 2,
      decreasePositionSwapType: 0,
      isLong: true,
      shouldUnwrapNativeToken: false,
      autoCancel: false, // Set true to enable auto-cancellation
      referralCode: ethers.utils.formatBytes32String(""), // Set a referral code if any
    };

    // Encode the function data
    const createOrderABI = iGmxExchangeRouter.encodeFunctionData("createOrder", [createOrderParams]);

    const multicallTxs = [sendGasTokensABI];
    if (!params.decreasePosition) multicallTxs.push(sendCollateralTokensABI);
    if (!params.onlySendTokens) multicallTxs.push(createOrderABI);

    await whitelistedPoolLogic
      .connect(manager)
      .execTransaction(testParams.exchangeRouter, iGmxExchangeRouter.encodeFunctionData("multicall", [multicallTxs]));
  };

  // utils.beforeAfterReset(beforeEach, afterEach);

  describe("Leverage Checks", () => {
    it("Can't open order if leverage is too high", async () => {
      const leverage = 8;

      const initialCollateralDeltaAmount = perpCollateral.amount.div(2);

      const collateralValue = await whitelistedManagerLogic["assetValue(address,uint256)"](
        perpCollateral.address,
        initialCollateralDeltaAmount,
      );

      // sizeDeltaUsd is always in 30 decimals
      const sizeDeltaUsd = collateralValue.mul(1e12).mul(leverage);
      await expect(openOrder({ initialCollateralDeltaAmount, sizeDeltaUsd })).to.revertedWith("max leverage exceeded");
    });
    it("Can't adjust order to leverage that is too high", async () => {
      const originalLeverage = 3;
      const toLeverage = 8;
      const initialCollateralDeltaAmount = perpCollateral.amount.div(2);

      const collateralValue = await whitelistedManagerLogic["assetValue(address,uint256)"](
        perpCollateral.address,
        initialCollateralDeltaAmount,
      );
      // sizeDeltaUsd is always in 30 decimals
      const sizeDeltaUsd = collateralValue.mul(1e12).mul(originalLeverage);
      const collateralErc20 = await ethers.getContractAt("IERC20Extended", testParams.vaultCollateralAsset);
      const collateralBalBefore = await collateralErc20.balanceOf(whitelistedPoolLogic.address);
      await openOrder({ initialCollateralDeltaAmount, sizeDeltaUsd });

      await executeOrder({
        tokens: [testParams.longCollateral.address, testParams.shortCollateral.address],
        account: whitelistedPoolLogic.address,
        testParams,
        type: "ORDER",
      });
      const collateralBalAfter = await collateralErc20.balanceOf(whitelistedPoolLogic.address);
      assert(collateralBalAfter.lt(collateralBalBefore), "order executed; collateral balance should decrease");

      // case 1:  increase the size to increase leverage
      const sizeDeltaUsdNew1 = collateralValue.mul(1e12).mul(toLeverage).sub(sizeDeltaUsd);
      await expect(
        openOrder({ initialCollateralDeltaAmount: ethers.constants.Zero, sizeDeltaUsd: sizeDeltaUsdNew1 }),
      ).to.revertedWith("max leverage exceeded");

      // case 2: withdraw the margin to increase leverage
      const resultingCollateralAmount = initialCollateralDeltaAmount.mul(originalLeverage).div(toLeverage);
      const collateralDelta = initialCollateralDeltaAmount.sub(resultingCollateralAmount);
      await expect(
        openOrder({
          decreasePosition: true,
          initialCollateralDeltaAmount: collateralDelta,
          sizeDeltaUsd: ethers.constants.Zero,
        }),
      ).to.revertedWith("max leverage exceeded");
    });
  });

  describe("Gmx Perps Order Checks", () => {
    it("Can't open order if market is not enabled", async () => {
      await utils.evmRestoreSnap(snap1);
      await whitelistedManagerLogic.connect(manager).changeAssets([], [testParams.market]);
      await expect(openOrder({})).to.revertedWith("unsupported market");
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
    it("Can't open order with wrong fee receiver", async () => {
      await expect(openOrder({ uiFeeReceiver: DUMMY_ADDRESS })).to.revertedWith("invalid fee receiver");
    });
    it("Can't open order with call back contract", async () => {
      await expect(openOrder({ callbackContract: DUMMY_ADDRESS })).to.revertedWith("invalid callback contract");
    });
    it("Can't open order with invalid oder vault", async () => {
      await expect(openOrder({ orderVault: DUMMY_ADDRESS })).to.revertedWith("invalid receiver");
    });
    it("Can't only send tokens without order", async () => {
      await expect(openOrder({ onlySendTokens: true })).to.revertedWith("invalid transaction");
    });
    it("Can open order", async () => {
      const totalFundValueBefore = await whitelistedManagerLogic.totalFundValue();
      await openOrder({});
      const totalFundValueAfterOrder = await whitelistedManagerLogic.totalFundValue();

      //Check if the collateral and gas (here also long token) are deposited
      await Promise.all(
        [testParams.gasToken, perpCollateral].map(async (oneAsset) => {
          const token = await ethers.getContractAt("IERC20Extended", oneAsset.address);
          expect((await token.balanceOf(oneAsset.address)).eq(oneAsset.amount.div(2)));
        }),
      );

      //No check on created order as it is implicit in asset guard (get token value from order)
      expect(totalFundValueAfterOrder).to.be.closeTo(
        totalFundValueBefore,
        totalFundValueBefore.div(10_000), // 0.01%
      );
      await executeOrder({
        tokens: [testParams.longCollateral.address, testParams.shortCollateral.address],
        account: whitelistedPoolLogic.address,
        testParams,
        type: "ORDER",
      });
      const totalFundValueAfterExec = await whitelistedManagerLogic.totalFundValue();
      expect(totalFundValueAfterOrder).to.be.closeTo(
        totalFundValueAfterExec,
        totalFundValueAfterExec.div(100), // 1% due to slippage and fees
      );
      //unused token for execution fee are sent back to the pool
      const gasToken = await ethers.getContractAt("IERC20Extended", testParams.gasToken.address);
      expect((await gasToken.balanceOf(whitelistedPoolLogic.address)).gt(testParams.gasToken.amount.div(2)));
    });
    it("Can open order with decrease size", async () => {
      const collateral = await ethers.getContractAt("IERC20Extended", perpCollateral.address);
      const collateralBalBefore1 = await collateral.balanceOf(whitelistedPoolLogic.address);
      await openOrder({
        sizeDeltaUsd: testParams.sizeAmount,
        initialCollateralDeltaAmount: perpCollateral.amount.div(4),
      });

      const collateralBalAfter1 = await collateral.balanceOf(whitelistedPoolLogic.address);
      // some collateral is sent to order vault
      expect(collateralBalBefore1).gt(collateralBalAfter1);
      await executeOrder({
        tokens: [testParams.longCollateral.address, testParams.shortCollateral.address],
        account: whitelistedPoolLogic.address,
        testParams,
        type: "ORDER",
      });
      const totalFundValueBefore = await whitelistedManagerLogic.totalFundValue();
      const collateralBalBefore2 = await collateral.balanceOf(whitelistedPoolLogic.address);
      await openOrder({ decreasePosition: true, initialCollateralDeltaAmount: perpCollateral.amount.div(8) });
      await executeOrder({
        tokens: [testParams.longCollateral.address, testParams.shortCollateral.address],
        account: whitelistedPoolLogic.address,
        testParams,
        type: "ORDER",
      });
      const collateralBalAfter2 = await collateral.balanceOf(whitelistedPoolLogic.address);
      expect(collateralBalAfter2.gt(collateralBalBefore2));
      const totalFundValueOrder = await whitelistedManagerLogic.totalFundValue();
      expect(totalFundValueOrder).to.be.closeTo(
        totalFundValueBefore,
        totalFundValueBefore.div(100), //1% due to slippage and fees
      );
    });
    it("Can open order with collateral different than the configured collateral asset", async function () {
      if (testParams.longCollateral.address === testParams.shortCollateral.address) {
        this.skip();
      }
      const totalFundValueBefore = await whitelistedManagerLogic.totalFundValue();

      const oppositeToken = selectOppositeCollateralToken({
        testParams,
      });
      const oppositeTokenAddress = selectOppositeCollateralToken({
        testParams,
      }).address;
      await openOrder({
        initialCollateralDeltaAmount: oppositeToken.amount.div(2),
        collateralToken: oppositeTokenAddress,
      });
      const totalFundValueAfterOrder = await whitelistedManagerLogic.totalFundValue();
      expect(totalFundValueAfterOrder).to.be.closeTo(
        totalFundValueBefore,
        totalFundValueBefore.div(10_000).mul(5), // 0.05%
      );

      await executeOrder({
        tokens: [testParams.longCollateral.address, testParams.shortCollateral.address],
        account: whitelistedPoolLogic.address,
        testParams,
        type: "ORDER",
      });
      const totalFundValueAfterExec = await whitelistedManagerLogic.totalFundValue();
      expect(totalFundValueAfterOrder).to.be.closeTo(
        totalFundValueAfterExec,
        totalFundValueAfterExec.div(100), // 1% due to slippage and fees
      );
    });
  });

  describe("Gmx Perps withdrawal checks", async () => {
    utils.beforeAfterReset(beforeEach, afterEach);
    it("Can't withdraw if not enough withdrawal asset in pool", async () => {
      await openOrder({
        sizeDeltaUsd: testParams.sizeAmount.div(4),
        initialCollateralDeltaAmount: perpCollateral.amount.div(8),
      });
      const ownerPoolTokenBalance = await whitelistedPoolLogic.balanceOf(logicOwner.address);
      // Withdraw 2/3 of the pool tokens
      const tokensToWithdraw = ownerPoolTokenBalance.mul(2).div(3);
      await expect(whitelistedPoolLogic.withdraw(tokensToWithdraw)).to.revertedWith("not enough available balance_1");
    });
    it("Can withdraw if enough withdrawal asset in pool", async () => {
      await openOrder({
        sizeDeltaUsd: testParams.sizeAmount.div(4),
        initialCollateralDeltaAmount: perpCollateral.amount.div(8),
      });
      await executeOrder({
        tokens: [testParams.longCollateral.address, testParams.shortCollateral.address],
        account: whitelistedPoolLogic.address,
        testParams,
        type: "ORDER",
      });
      const withdrawAsset = await ethers.getContractAt("IERC20Extended", testParams.vaultWithdrawalAsset);
      const totalFundValueBefore = await whitelistedManagerLogic.totalFundValue();
      const ownerPoolTokenBalanceBefore = await whitelistedPoolLogic.balanceOf(logicOwner.address);
      const withdrawAssetBalanceBefore = await withdrawAsset.balanceOf(logicOwner.address);

      const poolGmxAssetValueBeforeD18 = await whitelistedManagerLogic["assetBalance"](testParams.market);

      const poolWithdrawAssetValueBeforeD18 = await whitelistedManagerLogic["assetValue(address,uint256)"](
        testParams.vaultWithdrawalAsset,
        await withdrawAsset.balanceOf(whitelistedPoolLogic.address),
      );
      // Withdraw 10% of the pool tokens
      const tokensToWithdraw = ownerPoolTokenBalanceBefore.div(10);
      await whitelistedPoolLogic.withdraw(tokensToWithdraw);
      const poolGmxAssetValueAfterD18 = await whitelistedManagerLogic["assetBalance"](testParams.market);

      const poolWithdrawAssetValueAfterD18 = await whitelistedManagerLogic["assetValue(address,uint256)"](
        testParams.vaultWithdrawalAsset,
        await withdrawAsset.balanceOf(whitelistedPoolLogic.address),
      );

      const withdrawAssetBalanceAfter = await withdrawAsset.balanceOf(logicOwner.address);
      const withdrawAssetValueD18 = await whitelistedManagerLogic["assetValue(address,uint256)"](
        testParams.vaultWithdrawalAsset,
        withdrawAssetBalanceAfter.sub(withdrawAssetBalanceBefore),
      );
      const poolGmxWitdrawAssetDecreasedValue = poolGmxAssetValueBeforeD18
        .add(poolWithdrawAssetValueBeforeD18)
        .sub(poolGmxAssetValueAfterD18.add(poolWithdrawAssetValueAfterD18));
      const ownerPoolTokenBalanceAfter = await whitelistedPoolLogic.balanceOf(logicOwner.address);
      const totalFundValueAfter = await whitelistedManagerLogic.totalFundValue();
      expect(ownerPoolTokenBalanceBefore.sub(ownerPoolTokenBalanceAfter)).eq(tokensToWithdraw);
      expect(poolGmxWitdrawAssetDecreasedValue).to.be.closeTo(withdrawAssetValueD18, withdrawAssetValueD18.div(100)); // 1% due to slippage and fees
      expect(totalFundValueAfter).to.be.closeTo(
        totalFundValueBefore.mul(9).div(10),
        totalFundValueAfter.div(200), // 0.5%
      );
    });
  });
};
