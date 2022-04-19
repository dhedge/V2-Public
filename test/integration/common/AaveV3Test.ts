import { ethers } from "hardhat";
import { solidity } from "ethereum-waffle";
import { expect, use } from "chai";
import { checkAlmostSame, units } from "../../TestHelpers";
import {
  IERC20,
  IERC20__factory,
  ILendingPool__factory,
  PoolFactory,
  PoolLogic,
  PoolManagerLogic,
} from "../../../types";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { createFund } from "../utils/createFund";
import { getAccountToken } from "../utils/getAccountTokens";
import { deployContracts, IDeployments, NETWORK } from "../utils/deployContracts";
import { BigNumber } from "ethers";

use(solidity);

interface IAaveV3TestParameters {
  network: NETWORK;
  aaveLendingPool: string;
  weth: {
    address: string;
  };
  usdt: {
    address: string;
    balanceOfSlot: number;
    aToken: string;
  };
  usdc: {
    address: string;
    balanceOfSlot: number;
    aToken: string;
  };
  dai: {
    address: string;
    aToken: string;
  };
}

export const testAaveV3 = ({ network, aaveLendingPool, weth, usdt, usdc, dai }: IAaveV3TestParameters) => {
  describe("Aave V3 Test", function () {
    let USDC: IERC20, DAI: IERC20, AMUSDC: IERC20;
    let logicOwner: SignerWithAddress, manager: SignerWithAddress;
    let poolFactory: PoolFactory, poolLogicProxy: PoolLogic, poolManagerLogicProxy: PoolManagerLogic;
    let deployments: IDeployments;
    const iERC20 = new ethers.utils.Interface(IERC20__factory.abi);
    const iLendingPool = new ethers.utils.Interface(ILendingPool__factory.abi);

    before(async function () {
      [logicOwner, manager] = await ethers.getSigners();

      deployments = await deployContracts(network);
      poolFactory = deployments.poolFactory;

      DAI = await ethers.getContractAt("IERC20", dai.address);
      USDC = await ethers.getContractAt("IERC20", usdc.address);
      AMUSDC = await ethers.getContractAt("IERC20", usdc.aToken);

      await getAccountToken(units(100000, 6), logicOwner.address, usdc.address, usdc.balanceOfSlot);
    });

    let snapshot: unknown;
    afterEach(async () => {
      await ethers.provider.send("evm_revert", [snapshot]);
      await ethers.provider.send("evm_mine", []);
    });
    beforeEach(async function () {
      snapshot = await ethers.provider.send("evm_snapshot", []);
      await ethers.provider.send("evm_mine", []);
      const funds = await createFund(poolFactory, logicOwner, manager, [
        { asset: usdc.address, isDeposit: true },
        { asset: weth.address, isDeposit: true },
        { asset: usdt.address, isDeposit: false },
      ]);
      poolLogicProxy = funds.poolLogicProxy;
      poolManagerLogicProxy = funds.poolManagerLogicProxy;

      // Deposit 2M
      await USDC.approve(poolLogicProxy.address, units(20000, 6));
      await poolLogicProxy.deposit(usdc.address, units(20000, 6));

      await poolFactory.setExitCooldown(0);
    });

    it("Should not be able to borrow non lending enabled assets", async () => {
      // assert usdt is non lending
      expect(await deployments.assetHandler.assetTypes(usdt.address)).to.equal(0);

      const amount = units(10000, 6);
      await poolManagerLogicProxy.connect(manager).changeAssets([{ asset: aaveLendingPool, isDeposit: false }], []);
      const depositABI = iLendingPool.encodeFunctionData("deposit", [usdc.address, amount, poolLogicProxy.address, 0]);

      // approve usdc for aave
      const approveABI = iERC20.encodeFunctionData("approve", [aaveLendingPool, amount]);
      await poolLogicProxy.connect(manager).execTransaction(usdc.address, approveABI);
      // deposit usdc into aave
      await poolLogicProxy.connect(manager).execTransaction(aaveLendingPool, depositABI);

      const borrowABI = iLendingPool.encodeFunctionData("borrow", [
        usdt.address,
        // We can only borrow a fraction of the collateral
        amount.div(3),
        2,
        0,
        poolLogicProxy.address,
      ]);
      // Should no be able to borrow non lending assets
      expect(poolLogicProxy.connect(manager).execTransaction(aaveLendingPool, borrowABI)).to.be.revertedWith(
        "not borrow enabled",
      );
      // Simulate trading the borrowed usdt into something else
      await getAccountToken(BigNumber.from(0), poolLogicProxy.address, usdt.address, usdt.balanceOfSlot);
      // Should not be able to remove assets that have a respective aave debt
      await poolManagerLogicProxy.connect(manager).changeAssets([], [usdt.address]);
    });

    it("Should be able to deposit usdc and receive amusdc", async () => {
      // Pool balance: 2M USDC
      const amount = units(10000, 6);

      let depositABI = iLendingPool.encodeFunctionData("deposit", [usdc.address, amount, poolLogicProxy.address, 0]);

      await expect(
        poolLogicProxy.connect(manager).execTransaction(ethers.constants.AddressZero, depositABI),
      ).to.be.revertedWith("non-zero address is required");

      await expect(
        poolLogicProxy.connect(manager).execTransaction(poolLogicProxy.address, depositABI),
      ).to.be.revertedWith("Guard not found");

      // add supported assets
      await poolManagerLogicProxy.connect(manager).changeAssets([{ asset: aaveLendingPool, isDeposit: false }], []);

      // dai is not enabled in this pool
      depositABI = iLendingPool.encodeFunctionData("deposit", [dai.address, amount, poolLogicProxy.address, 0]);
      await expect(poolLogicProxy.connect(manager).execTransaction(aaveLendingPool, depositABI)).to.be.revertedWith(
        "unsupported deposit asset",
      );

      depositABI = iLendingPool.encodeFunctionData("deposit", [usdt.address, amount, poolLogicProxy.address, 0]);
      await expect(poolLogicProxy.connect(manager).execTransaction(aaveLendingPool, depositABI)).to.be.revertedWith(
        "not lending enabled",
      );

      depositABI = iLendingPool.encodeFunctionData("deposit", [usdc.address, amount, usdc.address, 0]);
      await expect(poolLogicProxy.connect(manager).execTransaction(aaveLendingPool, depositABI)).to.be.revertedWith(
        "recipient is not pool",
      );

      depositABI = iLendingPool.encodeFunctionData("deposit", [usdc.address, amount, poolLogicProxy.address, 0]);
      await expect(poolLogicProxy.connect(manager).execTransaction(usdc.address, depositABI)).to.be.revertedWith(
        "invalid transaction",
      );

      await expect(poolLogicProxy.connect(manager).execTransaction(aaveLendingPool, depositABI)).to.be.revertedWith(
        "ERC20: transfer amount exceeds allowance",
      );

      const usdcBalanceBefore = await USDC.balanceOf(poolLogicProxy.address);
      const amusdcBalanceBefore = await AMUSDC.balanceOf(poolLogicProxy.address);

      const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

      expect(usdcBalanceBefore).to.be.equal(units(20000, 6));
      expect(amusdcBalanceBefore).to.be.equal(0);

      // approve .usdc
      const approveABI = iERC20.encodeFunctionData("approve", [aaveLendingPool, amount]);
      await poolLogicProxy.connect(manager).execTransaction(usdc.address, approveABI);

      // deposit
      await poolLogicProxy.connect(manager).execTransaction(aaveLendingPool, depositABI);

      const usdcBalanceAfter = await USDC.balanceOf(poolLogicProxy.address);
      const amusdcBalanceAfter = await AMUSDC.balanceOf(poolLogicProxy.address);
      expect(usdcBalanceAfter).to.be.equal(amount);
      checkAlmostSame(amusdcBalanceAfter, amount);
      checkAlmostSame(await poolManagerLogicProxy.totalFundValue(), totalFundValueBefore);
    });

    describe("after deposit to aave", () => {
      beforeEach(async () => {
        // add supported assets
        await poolManagerLogicProxy.connect(manager).changeAssets([{ asset: aaveLendingPool, isDeposit: false }], []);

        const amount = units(10000, 6);

        // approve .usdc
        const approveABI = iERC20.encodeFunctionData("approve", [aaveLendingPool, amount]);
        await poolLogicProxy.connect(manager).execTransaction(usdc.address, approveABI);

        const depositABI = iLendingPool.encodeFunctionData("deposit", [
          usdc.address,
          amount,
          poolLogicProxy.address,
          0,
        ]);
        await poolLogicProxy.connect(manager).execTransaction(aaveLendingPool, depositABI);
      });

      it("Should be able to withdraw amusdc and receive usdc", async () => {
        // Pool balance: 0.8M USDC, 1M amUSDC, $0.2M in WETH
        const amount = units(5000, 6);

        let withdrawABI = iLendingPool.encodeFunctionData("withdraw", [usdc.address, amount, poolLogicProxy.address]);

        await expect(
          poolLogicProxy.connect(manager).execTransaction(ethers.constants.AddressZero, withdrawABI),
        ).to.be.revertedWith("non-zero address is required");

        await expect(
          poolLogicProxy.connect(manager).execTransaction(poolLogicProxy.address, withdrawABI),
        ).to.be.revertedWith("Guard not found");

        withdrawABI = iLendingPool.encodeFunctionData("withdraw", [usdt.aToken, amount, poolLogicProxy.address]);
        await expect(poolLogicProxy.connect(manager).execTransaction(aaveLendingPool, withdrawABI)).to.be.revertedWith(
          "unsupported withdraw asset",
        );
        withdrawABI = iLendingPool.encodeFunctionData("withdraw", [usdc.address, amount, usdc.address]);
        await expect(poolLogicProxy.connect(manager).execTransaction(aaveLendingPool, withdrawABI)).to.be.revertedWith(
          "recipient is not pool",
        );

        withdrawABI = iLendingPool.encodeFunctionData("withdraw", [usdc.address, amount, poolLogicProxy.address]);
        await expect(poolLogicProxy.connect(manager).execTransaction(usdc.address, withdrawABI)).to.be.revertedWith(
          "invalid transaction",
        );

        const usdcBalanceBefore = await USDC.balanceOf(poolLogicProxy.address);
        const amusdcBalanceBefore = await AMUSDC.balanceOf(poolLogicProxy.address);

        const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

        // withdraw
        await poolLogicProxy.connect(manager).execTransaction(aaveLendingPool, withdrawABI);

        const usdcBalanceAfter = await USDC.balanceOf(poolLogicProxy.address);
        const amusdcBalanceAfter = await AMUSDC.balanceOf(poolLogicProxy.address);
        checkAlmostSame(ethers.BigNumber.from(usdcBalanceBefore).add(amount), usdcBalanceAfter);
        checkAlmostSame(ethers.BigNumber.from(amusdcBalanceBefore).sub(amount), amusdcBalanceAfter);

        checkAlmostSame(await poolManagerLogicProxy.totalFundValue(), totalFundValueBefore);
      });

      it("Should be able to set reserve as collateral", async () => {
        // Pool balance: 1.5M USDC
        // Aave balance: 0.5M amUSDC

        const lendingPool = ILendingPool__factory.connect(aaveLendingPool, logicOwner);

        let abi = iLendingPool.encodeFunctionData("setUserUseReserveAsCollateral", [dai.address, true]);
        await expect(poolLogicProxy.connect(manager).execTransaction(aaveLendingPool, abi)).to.be.revertedWith(
          "unsupported asset",
        );

        abi = iLendingPool.encodeFunctionData("setUserUseReserveAsCollateral", [weth.address, true]);
        await expect(poolLogicProxy.connect(manager).execTransaction(aaveLendingPool, abi)).to.be.revertedWith("43");

        abi = iLendingPool.encodeFunctionData("setUserUseReserveAsCollateral", [usdc.address, false]);
        await poolLogicProxy.connect(manager).execTransaction(aaveLendingPool, abi);

        const userConfigBefore = await lendingPool.getUserConfiguration(poolLogicProxy.address);

        abi = iLendingPool.encodeFunctionData("setUserUseReserveAsCollateral", [usdc.address, true]);
        await poolLogicProxy.connect(manager).execTransaction(aaveLendingPool, abi);

        const userConfigAfter = await lendingPool.getUserConfiguration(poolLogicProxy.address);
        expect(userConfigBefore).to.be.not.equal(userConfigAfter);
      });

      it("should be able to withdraw 20%", async function () {
        // Pool balance: 1M USDC
        // Aave balance: 1M amUSDC

        // Withdraw 20%
        const withdrawAmount = units(4000);

        const usdcBalanceBefore = ethers.BigNumber.from(await USDC.balanceOf(poolLogicProxy.address));
        const totalFundValueBefore = ethers.BigNumber.from(await poolManagerLogicProxy.totalFundValue());
        const userUsdcBalanceBefore = await USDC.balanceOf(logicOwner.address);

        await poolLogicProxy.withdraw(withdrawAmount);

        checkAlmostSame(await poolManagerLogicProxy.totalFundValue(), totalFundValueBefore.mul(80).div(100));
        const usdcBalanceAfter = await USDC.balanceOf(poolLogicProxy.address);
        checkAlmostSame(usdcBalanceAfter, usdcBalanceBefore.sub(units(2000, 6)));
        const userUsdcBalanceAfter = await USDC.balanceOf(logicOwner.address);
        checkAlmostSame(userUsdcBalanceAfter, userUsdcBalanceBefore.add(units(2000, 6)).add(units(2000, 6)));
      });

      it("Should be able to borrow DAI", async () => {
        // Pool balance: 1M USDC
        // Aave balance: 1M amUSDC

        const amount = units(2500).toString();

        let borrowABI = iLendingPool.encodeFunctionData("borrow", [dai.address, amount, 2, 0, poolLogicProxy.address]);

        await expect(
          poolLogicProxy.connect(manager).execTransaction(ethers.constants.AddressZero, borrowABI),
        ).to.be.revertedWith("non-zero address is required");

        await expect(
          poolLogicProxy.connect(manager).execTransaction(poolLogicProxy.address, borrowABI),
        ).to.be.revertedWith("Guard not found");

        await poolManagerLogicProxy.connect(manager).changeAssets([{ asset: dai.address, isDeposit: false }], []);

        borrowABI = iLendingPool.encodeFunctionData("borrow", [dai.address, amount, 2, 0, usdc.address]);
        await expect(poolLogicProxy.connect(manager).execTransaction(aaveLendingPool, borrowABI)).to.be.revertedWith(
          "recipient is not pool",
        );

        borrowABI = iLendingPool.encodeFunctionData("borrow", [dai.address, amount, 2, 0, poolLogicProxy.address]);
        await expect(poolLogicProxy.connect(manager).execTransaction(dai.address, borrowABI)).to.be.revertedWith(
          "invalid transaction",
        );

        const daiBalanceBefore = await DAI.balanceOf(poolLogicProxy.address);

        const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

        expect(daiBalanceBefore).to.be.equal(0);

        // borrow
        await poolLogicProxy.connect(manager).execTransaction(aaveLendingPool, borrowABI);

        borrowABI = iLendingPool.encodeFunctionData("borrow", [usdc.address, amount, 2, 0, poolLogicProxy.address]);
        await expect(poolLogicProxy.connect(manager).execTransaction(aaveLendingPool, borrowABI)).to.be.revertedWith(
          "borrowing asset exists",
        );

        const daiBalanceAfter = await DAI.balanceOf(poolLogicProxy.address);
        expect(daiBalanceAfter).to.be.equal(units(2500));

        checkAlmostSame(await poolManagerLogicProxy.totalFundValue(), totalFundValueBefore);
      });

      describe("after borrow from aave", () => {
        beforeEach(async () => {
          // add supported assets
          await poolManagerLogicProxy.connect(manager).changeAssets([{ asset: dai.address, isDeposit: false }], []);

          const amount = units(2500).toString();
          const borrowABI = iLendingPool.encodeFunctionData("borrow", [
            dai.address,
            amount,
            2,
            0,
            poolLogicProxy.address,
          ]);
          await poolLogicProxy.connect(manager).execTransaction(aaveLendingPool, borrowABI);
        });

        it("Should be able to repay DAI", async () => {
          // Pool balance: 1M USDC, 0.25M DAI
          // Aave balance: 1M amUSDC, 0.25M debtDAI

          const amount = units(1000);

          let repayABI;

          repayABI = iLendingPool.encodeFunctionData("repay", [dai.aToken, amount, 2, poolLogicProxy.address]);
          await expect(poolLogicProxy.connect(manager).execTransaction(aaveLendingPool, repayABI)).to.be.revertedWith(
            "unsupported repay asset",
          );

          repayABI = iLendingPool.encodeFunctionData("repay", [dai.address, amount, 2, usdc.address]);
          await expect(poolLogicProxy.connect(manager).execTransaction(aaveLendingPool, repayABI)).to.be.revertedWith(
            "recipient is not pool",
          );

          repayABI = iLendingPool.encodeFunctionData("repay", [dai.address, amount, 2, poolLogicProxy.address]);
          await expect(poolLogicProxy.connect(manager).execTransaction(dai.address, repayABI)).to.be.revertedWith(
            "invalid transaction",
          );

          await expect(poolLogicProxy.connect(manager).execTransaction(aaveLendingPool, repayABI)).to.be.reverted;

          // approve dai
          const approveABI = iERC20.encodeFunctionData("approve", [aaveLendingPool, amount]);
          await poolLogicProxy.connect(manager).execTransaction(dai.address, approveABI);

          const daiBalanceBefore = await DAI.balanceOf(poolLogicProxy.address);
          expect(daiBalanceBefore).to.be.equal(units(2500));

          const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

          // repay
          await poolLogicProxy.connect(manager).execTransaction(aaveLendingPool, repayABI);

          const daiBalanceAfter = await DAI.balanceOf(poolLogicProxy.address);
          expect(daiBalanceAfter).to.be.equal(units(1500));

          checkAlmostSame(await poolManagerLogicProxy.totalFundValue(), totalFundValueBefore);
        });

        it("should be able to withdraw after borrow", async function () {
          // Pool balance: 1M USDC, 0.25 DAI
          // Aave balance: 1M amUSDC, 0.25 debtDAI

          // enable weth to check withdraw process
          await poolManagerLogicProxy.connect(manager).changeAssets([{ asset: weth.address, isDeposit: false }], []);

          // Withdraw 10%
          const withdrawAmount = units(2000);

          const usdcBalanceBefore = ethers.BigNumber.from(await USDC.balanceOf(logicOwner.address));
          const totalFundValueBefore = ethers.BigNumber.from(await poolManagerLogicProxy.totalFundValue());

          checkAlmostSame(totalFundValueBefore, units(20000));

          await poolLogicProxy.withdraw(withdrawAmount);

          const totalFundValueAfter = ethers.BigNumber.from(await poolManagerLogicProxy.totalFundValue());

          checkAlmostSame(totalFundValueAfter, totalFundValueBefore.mul(90).div(100));
          const usdcBalanceAfter = ethers.BigNumber.from(await USDC.balanceOf(logicOwner.address));
          checkAlmostSame(usdcBalanceAfter, usdcBalanceBefore.add((1200e6).toString()));
        });

        it("should be able to swap borrow rate mode", async function () {
          let swapRateABI = iLendingPool.encodeFunctionData("swapBorrowRateMode", [usdc.address, 1]);

          swapRateABI = iLendingPool.encodeFunctionData("swapBorrowRateMode", [dai.aToken, 1]);
          await expect(
            poolLogicProxy.connect(manager).execTransaction(aaveLendingPool, swapRateABI),
          ).to.be.revertedWith("unsupported asset");

          swapRateABI = iLendingPool.encodeFunctionData("swapBorrowRateMode", [usdc.address, 1]);
          await expect(
            poolLogicProxy.connect(manager).execTransaction(aaveLendingPool, swapRateABI),
          ).to.be.revertedWith("41");

          swapRateABI = iLendingPool.encodeFunctionData("swapBorrowRateMode", [dai.address, 1]);
          await expect(
            poolLogicProxy.connect(manager).execTransaction(aaveLendingPool, swapRateABI),
          ).to.be.revertedWith("41");

          swapRateABI = iLendingPool.encodeFunctionData("swapBorrowRateMode", [dai.address, 2]);
          await poolLogicProxy.connect(manager).execTransaction(aaveLendingPool, swapRateABI);
        });

        it("should be able to rebalance stable borrow rate", async function () {
          let rebalanceAPI;

          rebalanceAPI = iLendingPool.encodeFunctionData("rebalanceStableBorrowRate", [
            dai.aToken,
            poolLogicProxy.address,
          ]);
          await expect(
            poolLogicProxy.connect(manager).execTransaction(aaveLendingPool, rebalanceAPI),
          ).to.be.revertedWith("unsupported asset");

          rebalanceAPI = iLendingPool.encodeFunctionData("rebalanceStableBorrowRate", [usdc.address, weth.address]);
          await expect(
            poolLogicProxy.connect(manager).execTransaction(aaveLendingPool, rebalanceAPI),
          ).to.be.revertedWith("user is not pool");

          rebalanceAPI = iLendingPool.encodeFunctionData("rebalanceStableBorrowRate", [
            usdc.address,
            poolLogicProxy.address,
          ]);
          await expect(
            poolLogicProxy.connect(manager).execTransaction(aaveLendingPool, rebalanceAPI),
          ).to.be.revertedWith("44");

          rebalanceAPI = iLendingPool.encodeFunctionData("rebalanceStableBorrowRate", [
            dai.address,
            poolLogicProxy.address,
          ]);
          await expect(
            poolLogicProxy.connect(manager).execTransaction(aaveLendingPool, rebalanceAPI),
          ).to.be.revertedWith("44");
        });

        it("should fail to remove asset", async () => {
          expect(poolManagerLogicProxy.changeAssets([], [dai.address])).to.revertedWith("repay Aave debt first");
          expect(poolManagerLogicProxy.changeAssets([], [usdc.address])).to.revertedWith(
            "withdraw Aave collateral first",
          );
          expect(poolManagerLogicProxy.changeAssets([], [aaveLendingPool])).to.revertedWith(
            "clear your position first",
          );
          expect(poolManagerLogicProxy.changeAssets([], [weth.address])).to.revertedWith("clear your position first");
        });
      });
    });
  });
};
