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
  IGmxRoleStore__factory,
  GmxTimeKeyViewer,
  GmxExchangeRouterContractGuard,
} from "../../../../types";
import { deployGmxInfrastructure } from "./gmxDeploymentHelpers";
import { getAccountToken } from "../../utils/getAccountTokens";
import { assert, expect } from "chai";
import {
  deduplicateTestTokenByAddress,
  executeOrder,
  GmxTestTokenAssetInfo,
  hashData,
  hashString,
  IGmxTestsParams,
  selectTestTokenByAddress,
} from "./gmxTestHelpers";
import { checkAlmostSame, units } from "../../../testHelpers";
import { describe } from "mocha";

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
  isLong?: boolean;
  acceptablePrice?: BigNumber;
  callbackGasLimit?: BigNumber;
};

export const launchGmxClaimTests = (testParams: IGmxTestsParams) => {
  let deployments: IBackboneDeployments;
  let logicOwner: SignerWithAddress;
  let whitelistedPoolLogic: PoolLogic;
  let nftTracker: string;
  let gmxTimekeyViewer: GmxTimeKeyViewer;

  const iERC20 = new ethers.utils.Interface(IERC20__factory.abi);
  const iGmxExchangeRouter = IGmxExchangeRouter__factory.createInterface();

  let manager: SignerWithAddress;
  let whitelistedManagerLogic: PoolManagerLogic;

  let token: IERC20;
  let gmxExchangeRouterContractGuard: GmxExchangeRouterContractGuard;

  let perpCollateral: GmxTestTokenAssetInfo;

  before(async () => {
    deployments = await deployBackboneContracts(testParams);
    logicOwner = deployments.owner;
    manager = deployments.manager;

    const gmxInfrastucture = await deployGmxInfrastructure(deployments, testParams);

    const GmxTimekeyViewer = await ethers.getContractFactory("GmxTimeKeyViewer", {
      libraries: {
        GmxClaimableCollateralTrackerLib: gmxInfrastucture.gmxClaimableCollateralTrackerLib.address,
      },
    });
    gmxTimekeyViewer = await GmxTimekeyViewer.deploy();

    whitelistedPoolLogic = gmxInfrastucture.whitelistedPool.poolLogicProxy;
    whitelistedManagerLogic = gmxInfrastucture.whitelistedPool.poolManagerLogicProxy;
    nftTracker = gmxInfrastucture.nftTracker;
    gmxExchangeRouterContractGuard = gmxInfrastucture.gmxExchangeRouterContractGuard;

    const testAssets = deduplicateTestTokenByAddress([
      testParams.longCollateral,
      testParams.shortCollateral,
      testParams.gasToken,
    ]);
    await Promise.all(
      testAssets.map(async (oneAsset) => {
        await getAccountToken(oneAsset.amount.mul(10), logicOwner.address, oneAsset.address, oneAsset.balanceOfSlot);
        token = await ethers.getContractAt("IERC20Extended", oneAsset.address);
        await token.approve(whitelistedPoolLogic.address, ethers.constants.MaxUint256);
        await whitelistedPoolLogic.deposit(oneAsset.address, oneAsset.amount.mul(10));
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
  });

  //reusable functions
  const openOrder = async (params: GmxOrderParams, createBySigner?: SignerWithAddress) => {
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
      receiver: params.receiver ?? whitelistedPoolLogic.address,
      cancellationReceiver: ethers.constants.AddressZero,
      callbackContract: params.callbackContract ?? ethers.constants.AddressZero,
      uiFeeReceiver: params.uiFeeReceiver ?? testParams.uiFeeReceiver,
      market: testParams.market,
      initialCollateralToken: params.collateralToken ?? perpCollateral.address,
      swapPath: [],
    };

    const numbers = {
      sizeDeltaUsd,
      initialCollateralDeltaAmount: initialCollateralDeltaAmountInNumbers,
      triggerPrice: ethers.constants.Zero,
      acceptablePrice: !!params.acceptablePrice
        ? params.acceptablePrice
        : params.decreasePosition
          ? 0
          : ethers.constants.MaxUint256,
      executionFee: testParams.gasToken.amount.div(2),
      callbackGasLimit: params.callbackGasLimit ?? ethers.constants.Zero,
      minOutputAmount: ethers.constants.Zero,
      validFromTime: ethers.constants.Zero,
    };

    const createOrderParams = {
      addresses: addresses,
      numbers: numbers,
      orderType: params.decreasePosition ? 4 : 2,
      decreasePositionSwapType: 0,
      isLong: params.isLong ?? true,
      shouldUnwrapNativeToken: false,
      autoCancel: false, // Set true to enable auto-cancellation
      referralCode: ethers.utils.formatBytes32String(""), // Set a referral code if any
    };

    // Encode the function data
    const createOrderABI = iGmxExchangeRouter.encodeFunctionData("createOrder", [createOrderParams]);

    const multicallTxs = [sendGasTokensABI];
    if (!params.decreasePosition) multicallTxs.push(sendCollateralTokensABI);
    if (!params.onlySendTokens) multicallTxs.push(createOrderABI);

    if (createBySigner) {
      const exchangeRouter = await ethers.getContractAt("IGmxExchangeRouter", testParams.exchangeRouter);
      if (testParams.gasToken.address === perpCollateral.address) {
        await getAccountToken(
          testParams.gasToken.amount.mul(2),
          createBySigner.address,
          testParams.gasToken.address,
          testParams.gasToken.balanceOfSlot,
        );
        const token = await ethers.getContractAt("IERC20Extended", testParams.gasToken.address);
        await token.connect(createBySigner).approve(testParams.approvalRouter, ethers.constants.MaxUint256);
      } else {
        await getAccountToken(
          testParams.gasToken.amount.mul(2),
          createBySigner.address,
          testParams.gasToken.address,
          testParams.gasToken.balanceOfSlot,
        );
        await getAccountToken(
          initialCollateralDeltaAmount.mul(2),
          createBySigner.address,
          perpCollateral.address,
          perpCollateral.balanceOfSlot,
        );
        const token1 = await ethers.getContractAt("IERC20Extended", testParams.gasToken.address);
        await token1.connect(createBySigner).approve(testParams.approvalRouter, ethers.constants.MaxUint256);
        const token2 = await ethers.getContractAt("IERC20Extended", perpCollateral.address);
        await token2.connect(createBySigner).approve(testParams.approvalRouter, ethers.constants.MaxUint256);
      }

      await exchangeRouter.connect(createBySigner).multicall(multicallTxs);
      return;
    }
    await whitelistedPoolLogic
      .connect(manager)
      .execTransaction(testParams.exchangeRouter, iGmxExchangeRouter.encodeFunctionData("multicall", [multicallTxs]));
  };

  describe("Claim", () => {
    it("claim claimable collateral", async () => {
      // set negative impact factor to 1 wei so that negative price impact exceeds threshold.
      await setMaxPositionImpactFactorKey(testParams, manager);

      await ethers.provider.send("evm_mine", []);
      const timekeysLongPre = await gmxTimekeyViewer.callStatic.getAllClaimableCollateralTimeKeys(nftTracker, {
        account: whitelistedPoolLogic.address,
        market: testParams.market,
        token: testParams.longCollateral.address,
      });
      const timekeysShortPre = await gmxTimekeyViewer.callStatic.getAllClaimableCollateralTimeKeys(nftTracker, {
        account: whitelistedPoolLogic.address,
        market: testParams.market,
        token: testParams.shortCollateral.address,
      });
      expect(timekeysLongPre.length).to.be.equal(0);
      expect(timekeysShortPre.length).to.be.equal(0);
      const collateral = await ethers.getContractAt("IERC20Extended", perpCollateral.address);
      const balanceBefore1 = await collateral.balanceOf(whitelistedPoolLogic.address);
      // 1. pool opens a long position
      await openOrder({
        initialCollateralDeltaAmount: perpCollateral.amount.mul(2),
        sizeDeltaUsd: testParams.sizeAmount.mul(8),
        callbackContract: gmxExchangeRouterContractGuard.address,
        callbackGasLimit: units(2, 6),
      });
      await executeOrder({
        tokens: [testParams.longCollateral.address, testParams.shortCollateral.address],
        account: whitelistedPoolLogic.address,
        testParams,
        type: "ORDER",
      });
      console.log("1. pool opens a long position");
      const balanceAfter1 = await collateral.balanceOf(whitelistedPoolLogic.address);
      assert(balanceBefore1.sub(balanceAfter1).gt(0), "executeOrder 1 failed");
      // 2. logicOwner opens a big short position to make it skewed to short
      await openOrder(
        {
          initialCollateralDeltaAmount: perpCollateral.amount.mul(testParams.multiplerToImpactForClaimCollateralTest),
          sizeDeltaUsd: testParams.sizeAmount.mul(testParams.multiplerToImpactForClaimCollateralTest), //
          isLong: false,
          acceptablePrice: units(0, 1),
          receiver: logicOwner.address,
        },
        logicOwner,
      );
      const balanceBefore2 = await collateral.balanceOf(logicOwner.address);
      await executeOrder({
        tokens: [testParams.longCollateral.address, testParams.shortCollateral.address],
        account: logicOwner.address,
        testParams,
        type: "ORDER",
      });
      console.log(" 2. logicOwner opens a big short position to make it skewed to short");
      const balanceAfter2 = await collateral.balanceOf(logicOwner.address);
      console.log("balanceBefore2", balanceBefore2.toString());
      console.log("balanceAfter2", balanceAfter2.toString());
      assert(balanceBefore2.eq(balanceAfter2), "executeOrder 2 failed"); // no collateral returned
      // 3.  pool decreases the long position and expect there is negative price impact
      // what it means is (real negative price impact).abs() > abs(capped negative price impact).abs()
      // it will get collateral deducted by the real negative price impact
      // it will get claimable collateral accrued, which is the diff between the above two
      const balanceBefore3 = await collateral.balanceOf(whitelistedPoolLogic.address);
      const collateralDecreaseAmount = perpCollateral.amount.mul(2);
      await openOrder({
        initialCollateralDeltaAmount: collateralDecreaseAmount,
        sizeDeltaUsd: testParams.sizeAmount.mul(8),
        decreasePosition: true,
        callbackContract: gmxExchangeRouterContractGuard.address,
        callbackGasLimit: units(2, 6),
      });
      const poolValueBeforeDecrease = await whitelistedManagerLogic.totalFundValue();
      const poolCollateralBalanceBeforeDecrease = await collateral.balanceOf(whitelistedPoolLogic.address);
      await executeOrder({
        tokens: [testParams.longCollateral.address, testParams.shortCollateral.address],
        account: whitelistedPoolLogic.address,
        testParams,
        type: "ORDER",
      });
      console.log(" 3. pool decreases the long position and get claimable collateral accrued");
      const poolValueAfterDecrease = await whitelistedManagerLogic.totalFundValue();
      const poolCollateralBalanceAfterDecrease = await collateral.balanceOf(whitelistedPoolLogic.address);
      expect(poolCollateralBalanceAfterDecrease).to.be.gt(poolCollateralBalanceBeforeDecrease);
      expect(poolValueAfterDecrease).to.be.closeTo(
        poolValueBeforeDecrease,
        poolValueBeforeDecrease.div(1000).mul(995), //0.5% due to slippage and fees
      );
      const claimAmountLongToken = await gmxTimekeyViewer.callStatic.getTotalClaimableAmount(
        nftTracker,
        testParams.dataStore,
        {
          account: whitelistedPoolLogic.address,
          market: testParams.market,
          token: testParams.longCollateral.address,
        },
      );
      const timekeysLongToken = await gmxTimekeyViewer.callStatic.getAllClaimableCollateralTimeKeys(nftTracker, {
        account: whitelistedPoolLogic.address,
        market: testParams.market,
        token: testParams.longCollateral.address,
      });
      const timekeysShortToken = await gmxTimekeyViewer.callStatic.getAllClaimableCollateralTimeKeys(nftTracker, {
        account: whitelistedPoolLogic.address,
        market: testParams.market,
        token: testParams.shortCollateral.address,
      });
      console.log("timekeysLongToken", timekeysLongToken);
      console.log("timekeysShortToken", timekeysShortToken);
      expect(timekeysLongToken.length === 1 || timekeysShortToken.length === 1).to.be.true;

      const collateralReturnAmount = poolCollateralBalanceAfterDecrease.sub(poolCollateralBalanceBeforeDecrease);
      expect(collateralDecreaseAmount).to.be.closeTo(
        claimAmountLongToken.add(collateralReturnAmount),
        collateralDecreaseAmount.div(25),
      ); //4% due to slippage and fees
      const balanceAfter3 = await collateral.balanceOf(whitelistedPoolLogic.address);
      assert(balanceAfter3.sub(balanceBefore3).gt(0), "executeOrder 3 failed");
      const claimAmountShortToken = await gmxTimekeyViewer.callStatic.getTotalClaimableAmount(
        nftTracker,
        testParams.dataStore,
        {
          account: whitelistedPoolLogic.address,
          market: testParams.market,
          token: testParams.shortCollateral.address,
        },
      );

      expect(claimAmountLongToken.gt(0) || claimAmountShortToken.gt(0)).to.be.true;

      // change ClaimCollateralFactorKey config from 0 to 1 so it can claim the collateral
      const timekeyToUse = timekeysLongToken.length ? timekeysLongToken[0] : timekeysShortToken[0];
      const collateralTokenToUse = timekeysLongToken.length
        ? testParams.longCollateral.address
        : testParams.shortCollateral.address;

      // change ClaimCollateralFactorKey config from 0 to 1
      // so it can claim the collateral
      await setClaimCollateralFactorKey(timekeyToUse.toNumber(), collateralTokenToUse, testParams, manager);

      console.log("collateralDecreaseAmount", collateralDecreaseAmount.toString());
      console.log("claimAmountLongToken", claimAmountLongToken.toString());
      console.log("claimAmountShortToken", claimAmountShortToken.toString());
      console.log("collateralReturnAmount", collateralReturnAmount.toString());
      console.log("poolValueBeforeDecrease", poolValueBeforeDecrease.toString());
      console.log("poolValueAfterDecrease", poolValueAfterDecrease.toString());

      const collateralBalanceBeforeClaim = await collateral.balanceOf(whitelistedPoolLogic.address);
      const poolValueBeforeClaim = await whitelistedManagerLogic.totalFundValue();
      // claim the claimable collateral
      const claimData = iGmxExchangeRouter.encodeFunctionData("claimCollateral", [
        [testParams.market],
        [collateralTokenToUse],
        [timekeyToUse],
        whitelistedPoolLogic.address,
      ]);
      await whitelistedPoolLogic.connect(manager).execTransaction(testParams.exchangeRouter, claimData, {
        gasLimit: units(2, 6),
      });
      const poolValueAfterClaim = await whitelistedManagerLogic.totalFundValue();
      const collateralBalanceAfterClaim = await collateral.balanceOf(whitelistedPoolLogic.address);
      expect(collateralBalanceAfterClaim.sub(collateralBalanceBeforeClaim)).to.be.eq(
        timekeysLongToken.length ? claimAmountLongToken : claimAmountShortToken,
      );

      checkAlmostSame(poolValueBeforeClaim, poolValueAfterClaim, 0.0000000001);
      console.log("collateralBalanceBeforeClaim", collateralBalanceBeforeClaim);
      console.log("collateralBalanceAfterClaim", collateralBalanceAfterClaim);

      const claimAmountLongAfter = await gmxTimekeyViewer.callStatic.getTotalClaimableAmount(
        nftTracker,
        testParams.dataStore,
        {
          account: whitelistedPoolLogic.address,
          market: testParams.market,
          token: testParams.longCollateral.address,
        },
      );
      const timekeysLongTokenAfter = await gmxTimekeyViewer.callStatic.getAllClaimableCollateralTimeKeys(nftTracker, {
        account: whitelistedPoolLogic.address,
        market: testParams.market,
        token: testParams.longCollateral.address,
      });
      console.log("claimAmountLongAfter", claimAmountLongAfter.toString());
      console.log("timekeysLongTokenAfter", timekeysLongTokenAfter.toString());

      const claimAmountShortAfter = await gmxTimekeyViewer.callStatic.getTotalClaimableAmount(
        nftTracker,
        testParams.dataStore,
        {
          account: whitelistedPoolLogic.address,
          market: testParams.market,
          token: testParams.shortCollateral.address,
        },
      );

      const timekeysShortTokenAfter = await gmxTimekeyViewer.callStatic.getAllClaimableCollateralTimeKeys(nftTracker, {
        account: whitelistedPoolLogic.address,
        market: testParams.market,
        token: testParams.shortCollateral.address,
      });

      // Cleanup checks
      expect(claimAmountLongAfter).to.be.eq(0);
      expect(claimAmountShortAfter).to.be.eq(0);
      expect(timekeysLongTokenAfter.length).to.be.eq(0);
      expect(timekeysShortTokenAfter.length).to.be.eq(0);
    });
  });
};
const impersonateController = async (params: IGmxTestsParams, signer: SignerWithAddress) => {
  const dataStore = await ethers.getContractAt("IGmxDataStore", params.dataStore);
  const roleStoreAddress = await dataStore.callStatic.roleStore();
  const roleStore = IGmxRoleStore__factory.connect(roleStoreAddress, signer);
  const controller = await roleStore.callStatic.getRoleMembers(hashString("CONTROLLER"), 0, 1);
  const controllerAddress = controller[0];
  const controllerSigner = await utils.impersonateAccount(controllerAddress);
  return controllerSigner;
};

const setMaxPositionImpactFactorKey = async (params: IGmxTestsParams, signer: SignerWithAddress) => {
  function maxPositionImpactFactorKey(marketAddress, isPositive) {
    return hashData(
      ["bytes32", "address", "bool"],
      [hashString("MAX_POSITION_IMPACT_FACTOR"), marketAddress, isPositive],
    );
  }

  const dataStore = await ethers.getContractAt("IGmxDataStore", params.dataStore);
  const controllerSigner = await impersonateController(params, signer);
  // set negative impact factor to 1 wei so that negative price impact exceeds threshold.
  // negative impact factor < negative price impact is necessary for claimable collateral to accrue
  await dataStore.connect(controllerSigner).setUint(maxPositionImpactFactorKey(params.market, false), 1);
};

const setClaimCollateralFactorKey = async (
  timekey: number,
  setCollateralAddress: string,
  params: IGmxTestsParams,
  signer: SignerWithAddress,
) => {
  const CLAIMABLE_COLLATERAL_FACTOR = hashString("CLAIMABLE_COLLATERAL_FACTOR");
  function claimableCollateralFactorKey(market: string, token: string, timeKey: number) {
    return hashData(
      ["bytes32", "address", "address", "uint256"],
      [CLAIMABLE_COLLATERAL_FACTOR, market, token, timeKey],
    );
  }
  const dataStore = await ethers.getContractAt("IGmxDataStore", params.dataStore);
  const controllerSigner = await impersonateController(params, signer);
  await dataStore
    .connect(controllerSigner)
    .setUint(claimableCollateralFactorKey(params.market, setCollateralAddress, timekey), units(1, 30));
};
