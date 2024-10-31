import { ethers } from "hardhat";
import { expect } from "chai";
import { checkAlmostSame, units } from "../../../testHelpers";
import { polygonChainData } from "../../../../config/chainData/polygonData";
import {
  IAaveIncentivesController__factory,
  IERC20,
  IERC20__factory,
  ILendingPool__factory,
  PoolFactory,
  PoolLogic,
  PoolManagerLogic,
} from "../../../../types";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { createFund } from "../../utils/createFund";
import { getAccountToken } from "../../utils/getAccountTokens";
import { deployContracts, IDeployments } from "../../utils/deployContracts/deployContracts";
import { BigNumber } from "ethers";
import { utils } from "../../utils/utils";

const { sushi, aaveV2, assets, assetsBalanceOfSlot } = polygonChainData;

describe("Aave Test", function () {
  let USDC: IERC20, DAI: IERC20, AMUSDC: IERC20, WMATIC: IERC20;
  let logicOwner: SignerWithAddress, manager: SignerWithAddress;
  let poolFactory: PoolFactory, poolLogicProxy: PoolLogic, poolManagerLogicProxy: PoolManagerLogic;
  const iERC20 = new ethers.utils.Interface(IERC20__factory.abi);
  const iLendingPool = new ethers.utils.Interface(ILendingPool__factory.abi);
  let deployments: IDeployments;

  before(async function () {
    [logicOwner, manager] = await ethers.getSigners();

    deployments = await deployContracts("polygon");
    poolFactory = deployments.poolFactory;
    DAI = deployments.assets.DAI;
    USDC = deployments.assets.USDC;
    // eslint-disable-next-line @typescript-eslint/no-non-null-assertion
    WMATIC = deployments.assets.WMATIC!;
    // eslint-disable-next-line @typescript-eslint/no-non-null-assertion
    AMUSDC = deployments.assets.AMUSDC!;

    await getAccountToken(units(10000, 6), logicOwner.address, assets.usdc, assetsBalanceOfSlot.usdc);
  });

  let snapId: string;

  afterEach(async () => {
    await utils.evmRestoreSnap(snapId);
  });

  beforeEach(async function () {
    snapId = await utils.evmTakeSnap();
    await ethers.provider.send("evm_mine", []);
    const funds = await createFund(poolFactory, logicOwner, manager, [
      { asset: assets.usdc, isDeposit: true },
      { asset: assets.weth, isDeposit: true },
      { asset: assets.usdt, isDeposit: false },
    ]);
    poolLogicProxy = funds.poolLogicProxy;
    poolManagerLogicProxy = funds.poolManagerLogicProxy;

    // Deposit 200 USDC
    await USDC.approve(poolLogicProxy.address, (200e6).toString());
    await poolLogicProxy.deposit(assets.usdc, (200e6).toString());
  });

  it("Should not be able to borrow non lending enabled assets", async () => {
    // assert usdt is non lending
    expect(await deployments.assetHandler.assetTypes(assets.usdt)).to.equal(0);

    const amount = units(100, 6);
    await poolManagerLogicProxy.connect(manager).changeAssets([{ asset: aaveV2.lendingPool, isDeposit: false }], []);
    const depositABI = iLendingPool.encodeFunctionData("deposit", [assets.usdc, amount, poolLogicProxy.address, 0]);

    // approve usdc for aave
    const approveABI = iERC20.encodeFunctionData("approve", [aaveV2.lendingPool, amount]);
    await poolLogicProxy.connect(manager).execTransaction(assets.usdc, approveABI);
    // deposit usdc into aave
    await poolLogicProxy.connect(manager).execTransaction(aaveV2.lendingPool, depositABI);

    const borrowABI = iLendingPool.encodeFunctionData("borrow", [
      assets.usdt,
      // We can only borrow a fraction of the collateral
      amount.div(3),
      2,
      0,
      poolLogicProxy.address,
    ]);
    // Should no be able to borrow non lending assets
    expect(poolLogicProxy.connect(manager).execTransaction(aaveV2.lendingPool, borrowABI)).to.be.revertedWith(
      "not borrow enabled",
    );
    // Simulate trading the borrowed usdt into something else
    await getAccountToken(BigNumber.from(0), poolLogicProxy.address, assets.usdt, assetsBalanceOfSlot.usdt);
    // Should not be able to remove assets that have a respective aave debt
    await poolManagerLogicProxy.connect(manager).changeAssets([], [assets.usdt]);
  });

  it("Should be able to deposit usdc and receive amusdc", async () => {
    // Pool balance: 200 USDC
    const amount = (100e6).toString();

    let depositABI = iLendingPool.encodeFunctionData("deposit", [assets.usdc, amount, poolLogicProxy.address, 0]);

    await expect(
      poolLogicProxy.connect(manager).execTransaction(poolLogicProxy.address, depositABI),
    ).to.be.revertedWith("invalid transaction");

    // add supported assets
    await poolManagerLogicProxy.connect(manager).changeAssets([{ asset: aaveV2.lendingPool, isDeposit: false }], []);

    // dai is not enabled in this pool
    depositABI = iLendingPool.encodeFunctionData("deposit", [assets.dai, amount, poolLogicProxy.address, 0]);
    await expect(poolLogicProxy.connect(manager).execTransaction(aaveV2.lendingPool, depositABI)).to.be.revertedWith(
      "unsupported deposit asset",
    );

    depositABI = iLendingPool.encodeFunctionData("deposit", [assets.usdt, amount, poolLogicProxy.address, 0]);
    await expect(poolLogicProxy.connect(manager).execTransaction(aaveV2.lendingPool, depositABI)).to.be.revertedWith(
      "not lending enabled",
    );

    depositABI = iLendingPool.encodeFunctionData("deposit", [assets.usdc, amount, assets.usdc, 0]);
    await expect(poolLogicProxy.connect(manager).execTransaction(aaveV2.lendingPool, depositABI)).to.be.revertedWith(
      "recipient is not pool",
    );

    depositABI = iLendingPool.encodeFunctionData("deposit", [assets.usdc, amount, poolLogicProxy.address, 0]);
    await expect(poolLogicProxy.connect(manager).execTransaction(assets.usdc, depositABI)).to.be.revertedWith(
      "invalid transaction",
    );

    await expect(poolLogicProxy.connect(manager).execTransaction(aaveV2.lendingPool, depositABI)).to.be.revertedWith(
      "SafeERC20: low-level call failed",
    );

    const usdcBalanceBefore = await USDC.balanceOf(poolLogicProxy.address);
    const amusdcBalanceBefore = await AMUSDC.balanceOf(poolLogicProxy.address);

    const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

    expect(usdcBalanceBefore).to.be.equal((200e6).toString());
    expect(amusdcBalanceBefore).to.be.equal(0);

    // approve .usdc
    const approveABI = iERC20.encodeFunctionData("approve", [aaveV2.lendingPool, amount]);
    await poolLogicProxy.connect(manager).execTransaction(assets.usdc, approveABI);

    // deposit
    await poolLogicProxy.connect(manager).execTransaction(aaveV2.lendingPool, depositABI);

    const usdcBalanceAfter = await USDC.balanceOf(poolLogicProxy.address);
    const amusdcBalanceAfter = await AMUSDC.balanceOf(poolLogicProxy.address);
    expect(usdcBalanceAfter).to.be.equal((100e6).toString());
    checkAlmostSame(amusdcBalanceAfter, 100e6);
    checkAlmostSame(await poolManagerLogicProxy.totalFundValue(), totalFundValueBefore);
  });

  describe("after deposit to aave", () => {
    beforeEach(async () => {
      // add supported assets
      await poolManagerLogicProxy.connect(manager).changeAssets([{ asset: aaveV2.lendingPool, isDeposit: false }], []);

      const amount = (100e6).toString();

      // approve .usdc
      const approveABI = iERC20.encodeFunctionData("approve", [aaveV2.lendingPool, amount]);
      await poolLogicProxy.connect(manager).execTransaction(assets.usdc, approveABI);

      const depositABI = iLendingPool.encodeFunctionData("deposit", [assets.usdc, amount, poolLogicProxy.address, 0]);
      await poolLogicProxy.connect(manager).execTransaction(aaveV2.lendingPool, depositABI);
    });

    it("Should be able to withdraw amusdc and receive usdc", async () => {
      // Pool balance: 80 USDC, 100 amUSDC, $20 in WETH
      const amount = (50e6).toString();

      let withdrawABI = iLendingPool.encodeFunctionData("withdraw", [assets.usdc, amount, poolLogicProxy.address]);

      await expect(
        poolLogicProxy.connect(manager).execTransaction(poolLogicProxy.address, withdrawABI),
      ).to.be.revertedWith("invalid transaction");

      withdrawABI = iLendingPool.encodeFunctionData("withdraw", [aaveV2.aTokens.usdt, amount, poolLogicProxy.address]);
      await expect(poolLogicProxy.connect(manager).execTransaction(aaveV2.lendingPool, withdrawABI)).to.be.revertedWith(
        "unsupported withdraw asset",
      );
      withdrawABI = iLendingPool.encodeFunctionData("withdraw", [assets.usdc, amount, assets.usdc]);
      await expect(poolLogicProxy.connect(manager).execTransaction(aaveV2.lendingPool, withdrawABI)).to.be.revertedWith(
        "recipient is not pool",
      );

      withdrawABI = iLendingPool.encodeFunctionData("withdraw", [assets.usdc, amount, poolLogicProxy.address]);
      await expect(poolLogicProxy.connect(manager).execTransaction(assets.usdc, withdrawABI)).to.be.revertedWith(
        "invalid transaction",
      );

      const usdcBalanceBefore = await USDC.balanceOf(poolLogicProxy.address);
      const amusdcBalanceBefore = await AMUSDC.balanceOf(poolLogicProxy.address);

      const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

      // withdraw
      await poolLogicProxy.connect(manager).execTransaction(aaveV2.lendingPool, withdrawABI);

      const usdcBalanceAfter = await USDC.balanceOf(poolLogicProxy.address);
      const amusdcBalanceAfter = await AMUSDC.balanceOf(poolLogicProxy.address);
      checkAlmostSame(ethers.BigNumber.from(usdcBalanceBefore).add(amount), usdcBalanceAfter);
      checkAlmostSame(ethers.BigNumber.from(amusdcBalanceBefore).sub(amount), amusdcBalanceAfter);

      checkAlmostSame(await poolManagerLogicProxy.totalFundValue(), totalFundValueBefore);
    });

    it("Should be able to set reserve as collateral", async () => {
      // Pool balance: 150 USDC
      // Aave balance: 50 amUSDC

      const lendingPool = ILendingPool__factory.connect(aaveV2.lendingPool, logicOwner);

      let abi = iLendingPool.encodeFunctionData("setUserUseReserveAsCollateral", [assets.dai, true]);
      await expect(poolLogicProxy.connect(manager).execTransaction(aaveV2.lendingPool, abi)).to.be.revertedWith(
        "unsupported asset",
      );

      abi = iLendingPool.encodeFunctionData("setUserUseReserveAsCollateral", [assets.weth, true]);
      await expect(poolLogicProxy.connect(manager).execTransaction(aaveV2.lendingPool, abi)).to.be.revertedWith("19");

      abi = iLendingPool.encodeFunctionData("setUserUseReserveAsCollateral", [assets.usdc, false]);
      await poolLogicProxy.connect(manager).execTransaction(aaveV2.lendingPool, abi);

      const userConfigBefore = await lendingPool.getUserConfiguration(poolLogicProxy.address);

      abi = iLendingPool.encodeFunctionData("setUserUseReserveAsCollateral", [assets.usdc, true]);
      await poolLogicProxy.connect(manager).execTransaction(aaveV2.lendingPool, abi);

      const userConfigAfter = await lendingPool.getUserConfiguration(poolLogicProxy.address);
      expect(userConfigBefore).to.be.not.equal(userConfigAfter);
    });

    it("should be able to withdraw 20%", async function () {
      // Pool balance: 100 USDC
      // Aave balance: 100 amUSDC

      // Withdraw 20%
      const withdrawAmount = units(40);

      const usdcBalanceBefore = ethers.BigNumber.from(await USDC.balanceOf(poolLogicProxy.address));
      const totalFundValueBefore = ethers.BigNumber.from(await poolManagerLogicProxy.totalFundValue());
      const userUsdcBalanceBefore = await USDC.balanceOf(logicOwner.address);

      await ethers.provider.send("evm_increaseTime", [86400]);
      await poolLogicProxy.withdraw(withdrawAmount);

      checkAlmostSame(await poolManagerLogicProxy.totalFundValue(), totalFundValueBefore.mul(80).div(100));
      const usdcBalanceAfter = await USDC.balanceOf(poolLogicProxy.address);
      checkAlmostSame(usdcBalanceAfter, usdcBalanceBefore.sub("20000000"));
      const userUsdcBalanceAfter = await USDC.balanceOf(logicOwner.address);
      checkAlmostSame(userUsdcBalanceAfter, userUsdcBalanceBefore.add("20000000").add("20000000"));
    });

    it("Should be able to borrow DAI", async () => {
      // Pool balance: 100 USDC
      // Aave balance: 100 amUSDC

      const amount = units(25).toString();

      let borrowABI = iLendingPool.encodeFunctionData("borrow", [assets.dai, amount, 2, 0, poolLogicProxy.address]);

      await expect(
        poolLogicProxy.connect(manager).execTransaction(poolLogicProxy.address, borrowABI),
      ).to.be.revertedWith("invalid transaction");

      await poolManagerLogicProxy.connect(manager).changeAssets([{ asset: assets.dai, isDeposit: false }], []);

      borrowABI = iLendingPool.encodeFunctionData("borrow", [assets.dai, amount, 2, 0, assets.usdc]);
      await expect(poolLogicProxy.connect(manager).execTransaction(aaveV2.lendingPool, borrowABI)).to.be.revertedWith(
        "recipient is not pool",
      );

      borrowABI = iLendingPool.encodeFunctionData("borrow", [assets.dai, amount, 2, 0, poolLogicProxy.address]);
      await expect(poolLogicProxy.connect(manager).execTransaction(assets.dai, borrowABI)).to.be.revertedWith(
        "invalid transaction",
      );

      const daiBalanceBefore = await DAI.balanceOf(poolLogicProxy.address);

      const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

      expect(daiBalanceBefore).to.be.equal(0);

      // borrow
      await poolLogicProxy.connect(manager).execTransaction(aaveV2.lendingPool, borrowABI);

      borrowABI = iLendingPool.encodeFunctionData("borrow", [assets.usdc, amount, 2, 0, poolLogicProxy.address]);
      await expect(poolLogicProxy.connect(manager).execTransaction(aaveV2.lendingPool, borrowABI)).to.be.revertedWith(
        "borrowing asset exists",
      );

      const daiBalanceAfter = await DAI.balanceOf(poolLogicProxy.address);
      expect(daiBalanceAfter).to.be.equal(units(25));

      checkAlmostSame(await poolManagerLogicProxy.totalFundValue(), totalFundValueBefore);
    });

    describe("after borrow from aave", () => {
      beforeEach(async () => {
        // add supported assets
        await poolManagerLogicProxy.connect(manager).changeAssets([{ asset: assets.dai, isDeposit: false }], []);

        const amount = units(25).toString();
        const borrowABI = iLendingPool.encodeFunctionData("borrow", [assets.dai, amount, 2, 0, poolLogicProxy.address]);
        await poolLogicProxy.connect(manager).execTransaction(aaveV2.lendingPool, borrowABI);
      });

      it("Should be able to repay DAI", async () => {
        // Pool balance: 100 USDC, 25 DAI
        // Aave balance: 100 amUSDC, 25 debtDAI

        const amount = units(10);

        let repayABI;

        repayABI = iLendingPool.encodeFunctionData("repay", [aaveV2.aTokens.dai, amount, 2, poolLogicProxy.address]);
        await expect(poolLogicProxy.connect(manager).execTransaction(aaveV2.lendingPool, repayABI)).to.be.revertedWith(
          "unsupported repay asset",
        );

        repayABI = iLendingPool.encodeFunctionData("repay", [assets.dai, amount, 2, assets.usdc]);
        await expect(poolLogicProxy.connect(manager).execTransaction(aaveV2.lendingPool, repayABI)).to.be.revertedWith(
          "recipient is not pool",
        );

        repayABI = iLendingPool.encodeFunctionData("repay", [assets.dai, amount, 2, poolLogicProxy.address]);
        await expect(poolLogicProxy.connect(manager).execTransaction(assets.dai, repayABI)).to.be.revertedWith(
          "invalid transaction",
        );

        await expect(poolLogicProxy.connect(manager).execTransaction(aaveV2.lendingPool, repayABI)).to.be.revertedWith(
          "SafeERC20: low-level call failed",
        );

        // approve dai
        const approveABI = iERC20.encodeFunctionData("approve", [aaveV2.lendingPool, amount]);
        await poolLogicProxy.connect(manager).execTransaction(assets.dai, approveABI);

        const daiBalanceBefore = await DAI.balanceOf(poolLogicProxy.address);
        expect(daiBalanceBefore).to.be.equal(units(25));

        const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

        // repay
        await poolLogicProxy.connect(manager).execTransaction(aaveV2.lendingPool, repayABI);

        const daiBalanceAfter = await DAI.balanceOf(poolLogicProxy.address);
        expect(daiBalanceAfter).to.be.equal(units(15));

        checkAlmostSame(await poolManagerLogicProxy.totalFundValue(), totalFundValueBefore);
      });

      it("should be able to withdraw after borrow", async function () {
        // Pool balance: 100 USDC, 25 DAI
        // Aave balance: 100 amUSDC, 25 debtDAI

        // enable weth to check withdraw process
        await poolManagerLogicProxy.connect(manager).changeAssets([{ asset: assets.weth, isDeposit: false }], []);

        // Withdraw 10%
        const withdrawAmount = units(20);

        const usdcBalanceBefore = ethers.BigNumber.from(await USDC.balanceOf(logicOwner.address));
        const totalFundValueBefore = ethers.BigNumber.from(await poolManagerLogicProxy.totalFundValue());

        checkAlmostSame(totalFundValueBefore, units(200));

        // Unapprove WETH in Sushiswap to test conditional approval logic
        const approveABI = iERC20.encodeFunctionData("approve", [sushi.router, (0).toString()]);
        await poolLogicProxy.connect(manager).execTransaction(assets.weth, approveABI);

        await ethers.provider.send("evm_increaseTime", [86400]);
        await poolLogicProxy.withdraw(withdrawAmount);

        const totalFundValueAfter = ethers.BigNumber.from(await poolManagerLogicProxy.totalFundValue());

        checkAlmostSame(totalFundValueAfter, totalFundValueBefore.mul(90).div(100));
        const usdcBalanceAfter = ethers.BigNumber.from(await USDC.balanceOf(logicOwner.address));
        checkAlmostSame(usdcBalanceAfter, usdcBalanceBefore.add((12e6).toString()));
      });

      it("should be able to swap borrow rate mode", async function () {
        let swapRateABI = iLendingPool.encodeFunctionData("swapBorrowRateMode", [assets.usdc, 1]);

        swapRateABI = iLendingPool.encodeFunctionData("swapBorrowRateMode", [aaveV2.aTokens.dai, 1]);
        await expect(
          poolLogicProxy.connect(manager).execTransaction(aaveV2.lendingPool, swapRateABI),
        ).to.be.revertedWith("unsupported asset");

        swapRateABI = iLendingPool.encodeFunctionData("swapBorrowRateMode", [assets.usdc, 1]);
        await expect(
          poolLogicProxy.connect(manager).execTransaction(aaveV2.lendingPool, swapRateABI),
        ).to.be.revertedWith("17");

        swapRateABI = iLendingPool.encodeFunctionData("swapBorrowRateMode", [assets.dai, 1]);
        await expect(
          poolLogicProxy.connect(manager).execTransaction(aaveV2.lendingPool, swapRateABI),
        ).to.be.revertedWith("17");

        swapRateABI = iLendingPool.encodeFunctionData("swapBorrowRateMode", [assets.dai, 2]);
        await expect(
          poolLogicProxy.connect(manager).execTransaction(aaveV2.lendingPool, swapRateABI),
        ).to.be.revertedWith("only variable rate");
      });

      it("should be able to rebalance stable borrow rate", async function () {
        let rebalanceAPI;

        rebalanceAPI = iLendingPool.encodeFunctionData("rebalanceStableBorrowRate", [
          aaveV2.aTokens.dai,
          poolLogicProxy.address,
        ]);
        await expect(
          poolLogicProxy.connect(manager).execTransaction(aaveV2.lendingPool, rebalanceAPI),
        ).to.be.revertedWith("unsupported asset");

        rebalanceAPI = iLendingPool.encodeFunctionData("rebalanceStableBorrowRate", [assets.usdc, assets.weth]);
        await expect(
          poolLogicProxy.connect(manager).execTransaction(aaveV2.lendingPool, rebalanceAPI),
        ).to.be.revertedWith("user is not pool");

        rebalanceAPI = iLendingPool.encodeFunctionData("rebalanceStableBorrowRate", [
          assets.usdc,
          poolLogicProxy.address,
        ]);
        await expect(
          poolLogicProxy.connect(manager).execTransaction(aaveV2.lendingPool, rebalanceAPI),
        ).to.be.revertedWith("22");

        rebalanceAPI = iLendingPool.encodeFunctionData("rebalanceStableBorrowRate", [
          assets.dai,
          poolLogicProxy.address,
        ]);
        await expect(
          poolLogicProxy.connect(manager).execTransaction(aaveV2.lendingPool, rebalanceAPI),
        ).to.be.revertedWith("22");
      });

      // Skipped because its always failing because aaveIncentivesController keeps running out of matic
      it.skip("should be able to claim matic rewards", async function () {
        const iAaveIncentivesController = new ethers.utils.Interface(IAaveIncentivesController__factory.abi);
        let claimRewardsAbi = iAaveIncentivesController.encodeFunctionData("claimRewards", [
          [aaveV2.variableDebtTokens.dai],
          1,
          assets.dai,
        ]);

        const incentivesController = IAaveIncentivesController__factory.connect(
          aaveV2.incentivesController,
          logicOwner,
        );

        await ethers.provider.send("evm_increaseTime", [3600 * 24 * 10]); // add 10 day
        await ethers.provider.send("evm_mine", []);

        const amount = units(10);
        const repayABI = iLendingPool.encodeFunctionData("repay", [assets.dai, amount, 2, poolLogicProxy.address]);

        const approveABI = iERC20.encodeFunctionData("approve", [aaveV2.lendingPool, amount]);
        await poolLogicProxy.connect(manager).execTransaction(assets.dai, approveABI);
        await poolLogicProxy.connect(manager).execTransaction(aaveV2.lendingPool, repayABI);

        await ethers.provider.send("evm_increaseTime", [3600 * 24 * 10]); // add 10 day
        await ethers.provider.send("evm_mine", []);

        const remainingRewardsBefore = await incentivesController.getUserUnclaimedRewards(poolLogicProxy.address);
        expect(remainingRewardsBefore).to.be.gt(0);

        await expect(
          poolLogicProxy.connect(manager).execTransaction(aaveV2.incentivesController, claimRewardsAbi),
        ).to.be.revertedWith("unsupported reward asset");

        // add supported assets
        await poolManagerLogicProxy.connect(manager).changeAssets([{ asset: assets.wmatic, isDeposit: false }], []);

        await expect(
          poolLogicProxy.connect(manager).execTransaction(aaveV2.incentivesController, claimRewardsAbi),
        ).to.be.revertedWith("recipient is not pool");

        claimRewardsAbi = iAaveIncentivesController.encodeFunctionData("claimRewards", [
          [aaveV2.variableDebtTokens.dai],
          remainingRewardsBefore,
          poolLogicProxy.address,
        ]);

        const wmaticBalanceBefore = ethers.BigNumber.from(await WMATIC.balanceOf(poolLogicProxy.address));
        const totalFundValueBefore = ethers.BigNumber.from(await poolManagerLogicProxy.totalFundValue());

        await poolLogicProxy.connect(manager).execTransaction(aaveV2.incentivesController, claimRewardsAbi);

        const remainingRewardsAfter = await incentivesController.getUserUnclaimedRewards(poolLogicProxy.address);
        expect(remainingRewardsAfter).to.lt(remainingRewardsBefore);
        const totalFundValueAfter = ethers.BigNumber.from(await poolManagerLogicProxy.totalFundValue());
        expect(totalFundValueAfter).to.be.gt(totalFundValueBefore);
        const wmaticBalanceAfter = ethers.BigNumber.from(await WMATIC.balanceOf(poolLogicProxy.address));
        expect(wmaticBalanceAfter).to.be.gt(wmaticBalanceBefore);
      });

      it("should fail to remove asset", async () => {
        await getAccountToken(BigNumber.from("0"), poolLogicProxy.address, assets.dai, assetsBalanceOfSlot.dai);
        await expect(poolManagerLogicProxy.connect(manager).changeAssets([], [assets.dai])).to.revertedWith(
          "repay Aave debt first",
        );
        await getAccountToken(BigNumber.from("0"), poolLogicProxy.address, assets.usdc, assetsBalanceOfSlot.usdc);
        await expect(poolManagerLogicProxy.connect(manager).changeAssets([], [assets.usdc])).to.revertedWith(
          "withdraw Aave collateral first",
        );
        await expect(poolManagerLogicProxy.connect(manager).changeAssets([], [aaveV2.lendingPool])).to.revertedWith(
          "cannot remove non-empty asset",
        );
      });
    });
  });
});
