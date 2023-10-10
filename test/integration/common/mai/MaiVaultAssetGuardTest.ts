import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { ethers } from "hardhat";
import { Address } from "../../../../deployment/types";
import {
  IERC20,
  IERC20__factory,
  IStableQiVault,
  IStableQiVault__factory,
  PoolFactory,
  PoolLogic,
  PoolManagerLogic,
} from "../../../../types";
import { units } from "../../../testHelpers";
import { createFund } from "../../utils/createFund";
import { deployContracts, NETWORK } from "../../utils/deployContracts/deployContracts";
import { getAccountToken } from "../../utils/getAccountTokens";
import { utils } from "../../utils/utils";
import { deployMai } from "./maiDeployHelper";
import { BigNumber } from "ethers";
import { expect } from "chai";

export const MaiVaultAssetGuardTest = (
  network: NETWORK,
  maiData: {
    maiAddress: Address;
    maiPriceFeed: Address;
    maiVaultAddress: Address;
    maiVaultCollateralAsset: Address;
    maiVaultCollateralAssetBalanceOfSlot: number;
    usdc: Address;
    aaveV3LendingPool: Address;
    frontPromoter: number;
  },
) => {
  describe("MaiVaultAssetGuard Test", function () {
    const {
      maiVaultAddress,
      maiVaultCollateralAsset,
      maiVaultCollateralAssetBalanceOfSlot,
      frontPromoter,
      maiAddress,
      usdc,
    } = maiData;

    let COLLATERAL: IERC20, MAI: IERC20, USDC: IERC20;
    let logicOwner: SignerWithAddress, manager: SignerWithAddress, otherInvestor: SignerWithAddress;
    let poolFactory: PoolFactory, poolLogicProxy: PoolLogic, poolManagerLogicProxy: PoolManagerLogic;
    const iERC20 = new ethers.utils.Interface(IERC20__factory.abi);
    const iMaiVault = new ethers.utils.Interface(IStableQiVault__factory.abi);
    let maiVault: IStableQiVault;

    const investmentAmount = units(50);
    before(async function () {
      maiVault = await ethers.getContractAt("IStableQiVault", maiVaultAddress);
      [logicOwner, manager, otherInvestor] = await ethers.getSigners();
      const deployments = await deployContracts(network);
      await deployMai(deployments, maiData);
      poolFactory = deployments.poolFactory;
      await poolFactory.setExitCooldown(0);

      COLLATERAL = <IERC20>await ethers.getContractAt(IERC20__factory.abi, maiVaultCollateralAsset);
      MAI = <IERC20>await ethers.getContractAt(IERC20__factory.abi, maiAddress);
      USDC = <IERC20>await ethers.getContractAt(IERC20__factory.abi, usdc);

      await getAccountToken(
        investmentAmount,
        logicOwner.address,
        COLLATERAL.address,
        maiVaultCollateralAssetBalanceOfSlot,
      );

      const funds = await createFund(
        poolFactory,
        logicOwner,
        manager,
        [
          { asset: maiVaultCollateralAsset, isDeposit: true },
          { asset: maiVaultAddress, isDeposit: false },
          { asset: maiAddress, isDeposit: false },
        ],
        {
          performance: ethers.BigNumber.from("0"),
          management: ethers.BigNumber.from("0"),
        },
      );
      poolLogicProxy = funds.poolLogicProxy;
      poolManagerLogicProxy = funds.poolManagerLogicProxy;

      await COLLATERAL.approve(poolLogicProxy.address, investmentAmount);
      await poolLogicProxy.deposit(COLLATERAL.address, investmentAmount);

      const approveABI = iERC20.encodeFunctionData("approve", [maiVaultAddress, investmentAmount]);
      await poolLogicProxy.connect(manager).execTransaction(COLLATERAL.address, approveABI);

      // Investor has no previous balance
      expect(await MAI.balanceOf(logicOwner.address)).to.equal(0);
      expect(await COLLATERAL.balanceOf(logicOwner.address)).to.equal(0);
      expect(await USDC.balanceOf(logicOwner.address)).to.equal(0);
    });

    utils.beforeAfterReset(beforeEach, afterEach);

    const createVault = async (): Promise<BigNumber> => {
      const createVault = iMaiVault.encodeFunctionData("createVault");
      await poolLogicProxy.connect(manager).execTransaction(maiVaultAddress, createVault);
      return (await maiVault.vaultCount()).sub(1);
    };

    const depositCollateral = async (vaultId: BigNumber, amount: BigNumber) => {
      const depositCollateral = iMaiVault.encodeFunctionData("depositCollateral", [vaultId, amount]);
      await poolLogicProxy.connect(manager).execTransaction(maiVaultAddress, depositCollateral);
      return (await maiVault.vaultCount()).sub(1);
    };

    const borrowMai200PercentRatio = async (vaultId: BigNumber) => {
      const totalFundValue = await poolManagerLogicProxy.totalFundValue();
      // 200% collateralisation ratio
      const amountToBorrow = totalFundValue.div(2);
      const borrowMai = iMaiVault.encodeFunctionData("borrowToken", [vaultId, amountToBorrow, frontPromoter]);
      await poolLogicProxy.connect(manager).execTransaction(maiVaultAddress, borrowMai);
    };

    const payBack = async (vaultId: BigNumber, amount: BigNumber): Promise<BigNumber> => {
      const approveABI = iERC20.encodeFunctionData("approve", [maiVaultAddress, amount]);
      await poolLogicProxy.connect(manager).execTransaction(maiAddress, approveABI);

      const payBackToken = iMaiVault.encodeFunctionData("payBackToken", [vaultId, amount, frontPromoter]);
      await poolLogicProxy.connect(manager).execTransaction(maiVaultAddress, payBackToken);
      const payBackFee = maiVault.calculateFee(
        await maiVault.closingFee(),
        amount,
        await maiVault.promoter(frontPromoter),
      );
      return payBackFee;
    };

    const paybackTokenAll = async (vaultId: BigNumber): Promise<BigNumber> => {
      const deadLine = (await utils.currentBlockTimestamp()) + 1000;
      const debtBalance = await maiVault.vaultDebt(vaultId);

      const approveABI = iERC20.encodeFunctionData("approve", [maiVaultAddress, debtBalance]);
      await poolLogicProxy.connect(manager).execTransaction(maiAddress, approveABI);

      const paybackTokenAll = iMaiVault.encodeFunctionData("paybackTokenAll", [vaultId, deadLine, frontPromoter]);
      await poolLogicProxy.connect(manager).execTransaction(maiVaultAddress, paybackTokenAll);
      const payBackFee = maiVault.calculateFee(
        await maiVault.closingFee(),
        debtBalance,
        await maiVault.promoter(frontPromoter),
      );
      return payBackFee;
    };

    const withdrawCollateral = async (vaultId: BigNumber) => {
      const collateralAmount = await maiVault.vaultCollateral(vaultId);
      const withdrawCollateral = iMaiVault.encodeFunctionData("withdrawCollateral", [vaultId, collateralAmount]);
      await poolLogicProxy.connect(manager).execTransaction(maiVaultAddress, withdrawCollateral);
    };

    describe("Pricing", () => {
      it("no debt value is correct", async () => {
        const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

        const vaultId = await createVault();
        await depositCollateral(vaultId, investmentAmount);

        expect(totalFundValueBefore).to.equal(await poolManagerLogicProxy.totalFundValue());
      });

      it("with debt value is correct", async () => {
        const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

        const vaultId = await createVault();
        await depositCollateral(vaultId, investmentAmount);
        await borrowMai200PercentRatio(vaultId);

        expect(await poolManagerLogicProxy.totalFundValue()).to.be.closeTo(
          totalFundValueBefore,
          totalFundValueBefore.div(100),
        );
        expect(await poolManagerLogicProxy["assetValue(address)"](maiAddress)).to.be.closeTo(
          totalFundValueBefore.div(2),
          totalFundValueBefore.div(200),
        );
      });

      it("after partial payback value is correct", async () => {
        const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

        const vaultId = await createVault();
        await depositCollateral(vaultId, investmentAmount);
        await borrowMai200PercentRatio(vaultId);
        const payBackFee = await payBack(vaultId, (await maiVault.vaultDebt(vaultId)).div(2));

        // Payback fee comes out of collateral
        expect(await poolManagerLogicProxy.totalFundValue()).to.be.closeTo(
          totalFundValueBefore.sub(payBackFee),
          totalFundValueBefore.div(200),
        );
        // We should have 1/4 mai
        expect(await poolManagerLogicProxy["assetValue(address)"](maiAddress)).to.be.closeTo(
          totalFundValueBefore.div(4),
          totalFundValueBefore.div(200),
        );
      });

      it("after full payback value is correct", async () => {
        const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

        const vaultId = await createVault();
        await depositCollateral(vaultId, investmentAmount);
        await borrowMai200PercentRatio(vaultId);
        const payBackFee = await paybackTokenAll(vaultId);

        // Payback fee comes out of collateral
        expect(await poolManagerLogicProxy.totalFundValue()).to.be.closeTo(
          totalFundValueBefore.sub(payBackFee),
          totalFundValueBefore.div(200),
        );
        // We should have 0 mai
        expect(await poolManagerLogicProxy["assetValue(address)"](maiAddress)).to.equal(0);
      });

      it("after full payback and withdraw is correct", async () => {
        const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

        const vaultId = await createVault();
        await depositCollateral(vaultId, investmentAmount);
        await borrowMai200PercentRatio(vaultId);
        const payBackFee = await paybackTokenAll(vaultId);
        await withdrawCollateral(vaultId);

        // We should have 0 mai
        expect(await poolManagerLogicProxy["assetValue(address)"](COLLATERAL.address)).to.be.closeTo(
          totalFundValueBefore.sub(payBackFee),
          totalFundValueBefore.div(200),
        );
      });
    });

    describe("WithdrawProcessing", () => {
      const createVaultAndBorrow = async () => {
        const vaultId = await createVault();
        await depositCollateral(vaultId, investmentAmount);
        await borrowMai200PercentRatio(vaultId);
      };

      it("100% withdraw - no debt", async () => {
        const vaultId = await createVault();
        await depositCollateral(vaultId, investmentAmount);
        const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

        // 100% withdraw
        await poolLogicProxy.withdraw(await poolLogicProxy.balanceOf(logicOwner.address));

        const usdcAmountWithdrawn = await USDC.balanceOf(logicOwner.address);
        const usdcValue = await poolManagerLogicProxy["assetValue(address,uint256)"](USDC.address, usdcAmountWithdrawn);

        const totalValueWithdraw = usdcValue;

        expect(totalValueWithdraw).to.be.closeTo(totalFundValueBefore, totalFundValueBefore.div(100));
        expect(await poolManagerLogicProxy.totalFundValue()).to.equal(0);
      });

      it("50% withdraw - no debt", async () => {
        const vaultId = await createVault();
        await depositCollateral(vaultId, investmentAmount);
        const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

        // 50% withdraw
        await poolLogicProxy.withdraw((await poolLogicProxy.balanceOf(logicOwner.address)).div(2));

        const usdcAmountWithdrawn = await USDC.balanceOf(logicOwner.address);
        const usdcValue = await poolManagerLogicProxy["assetValue(address,uint256)"](USDC.address, usdcAmountWithdrawn);

        const totalValueWithdraw = usdcValue;

        expect(totalValueWithdraw).to.be.closeTo(totalFundValueBefore.div(2), totalFundValueBefore.div(100));
        expect(await poolManagerLogicProxy.totalFundValue()).to.be.closeTo(
          totalFundValueBefore.div(2),
          totalFundValueBefore.div(200),
        );
      });

      it("100% withdraw - with borrow - single investor", async () => {
        await createVaultAndBorrow();
        const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

        // 100% withdraw
        await poolLogicProxy.withdraw(await poolLogicProxy.balanceOf(logicOwner.address));

        const maiAmountWithdrawn = await MAI.balanceOf(logicOwner.address);
        const usdcAmountWithdrawn = await USDC.balanceOf(logicOwner.address);
        const maiValue = await poolManagerLogicProxy["assetValue(address,uint256)"](MAI.address, maiAmountWithdrawn);
        const usdcValue = await poolManagerLogicProxy["assetValue(address,uint256)"](USDC.address, usdcAmountWithdrawn);

        const totalValueWithdraw = maiValue.add(usdcValue);

        expect(await poolManagerLogicProxy.totalFundValue()).to.equal(0);
        expect(totalValueWithdraw).to.be.closeTo(totalFundValueBefore, totalFundValueBefore.div(100));
      });

      it("50% withdraw - with borrow - single investor", async () => {
        await createVaultAndBorrow();
        const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

        // 50% withdraw
        await poolLogicProxy.withdraw((await poolLogicProxy.balanceOf(logicOwner.address)).div(2));

        const maiAmountWithdrawn = await MAI.balanceOf(logicOwner.address);
        const usdcAmountWithdrawn = await USDC.balanceOf(logicOwner.address);
        const maiValue = await poolManagerLogicProxy["assetValue(address,uint256)"](MAI.address, maiAmountWithdrawn);
        const usdcValue = await poolManagerLogicProxy["assetValue(address,uint256)"](USDC.address, usdcAmountWithdrawn);

        const totalValueWithdraw = maiValue.add(usdcValue);

        expect(totalValueWithdraw).to.be.closeTo(totalFundValueBefore.div(2), totalFundValueBefore.div(200));
        expect(await poolManagerLogicProxy.totalFundValue()).to.be.closeTo(
          totalFundValueBefore.div(2),
          totalFundValueBefore.div(200),
        );
      });

      it("Two investors - 50% withdraw each", async () => {
        poolLogicProxy.transfer(otherInvestor.address, (await poolLogicProxy.balanceOf(logicOwner.address)).div(2));
        await createVaultAndBorrow();
        const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();
        await poolLogicProxy.withdraw((await poolLogicProxy.balanceOf(logicOwner.address)).div(2));
        await poolLogicProxy
          .connect(otherInvestor)
          .withdraw((await poolLogicProxy.balanceOf(otherInvestor.address)).div(2));

        for (const investor of [logicOwner, otherInvestor]) {
          const maiAmountWithdrawn = await MAI.balanceOf(investor.address);
          const usdcAmountWithdrawn = await USDC.balanceOf(investor.address);
          const maiValue = await poolManagerLogicProxy["assetValue(address,uint256)"](MAI.address, maiAmountWithdrawn);
          const usdcValue = await poolManagerLogicProxy["assetValue(address,uint256)"](
            USDC.address,
            usdcAmountWithdrawn,
          );

          const totalValueWithdraw = maiValue.add(usdcValue);

          expect(await poolManagerLogicProxy.totalFundValue()).to.be.closeTo(
            totalFundValueBefore.div(2),
            totalFundValueBefore.div(200),
          );
          expect(totalValueWithdraw).to.be.closeTo(totalFundValueBefore.div(4), totalFundValueBefore.div(200));
        }
      });
    });
  });
};
