import { ethers } from "hardhat";
import { expect } from "chai";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { checkAlmostSame, units } from "../../../testHelpers";
import { IERC20, PoolFactory, PoolLogic, PoolManagerLogic } from "../../../../types";
import { createFund } from "../../utils/createFund";
import { getAccountToken } from "../../utils/getAccountTokens";
import {
  IBackboneDeployments,
  deployBackboneContracts,
  iERC20,
} from "../../utils/deployContracts/deployBackboneContracts";
import { utils } from "../../utils/utils";
import {
  deployAaveV3TestInfrastructure,
  iLendingPool,
  IAaveV3TestParameters,
  getComplexAssetsData,
} from "./deployAaveV3TestInfrastructure";

export const AaveV3TrickTest = (testParams: IAaveV3TestParameters) => {
  describe("Aave V3 withdrawSafe Trick Test", () => {
    let deployments: IBackboneDeployments;
    let USDC: IERC20, WETH: IERC20;
    let logicOwner: SignerWithAddress, manager: SignerWithAddress;
    let poolFactory: PoolFactory, poolLogicProxy: PoolLogic, poolManagerLogicProxy: PoolManagerLogic;

    const baseAttack = async (attackType: 0 | 1) => {
      // Pool balance: 10000 USDC, 1 WETH
      // Aave balance: 10000 aUSDC, 1 debtWETH

      // some user deposits 20000 USDC
      await getAccountToken(
        units(20000, 6),
        deployments.user.address,
        USDC.address,
        testParams.assetsBalanceOfSlot.usdc,
      );
      // Pool balance: 40000 USDC, 1 WETH
      // Aave balance: 10000 aUSDC, 1 debtWETH
      await USDC.connect(deployments.user).approve(poolLogicProxy.address, units(20000, 6));
      await poolLogicProxy.connect(deployments.user).deposit(USDC.address, units(20000, 6));

      const someUserPoolTokenBalanceBefore = await poolLogicProxy.balanceOf(deployments.user.address);

      const AaveWithdrawTrickContract = await ethers.getContractFactory("AaveWithdrawTrickContract");
      const aaveWithdrawTrickContract = await AaveWithdrawTrickContract.deploy();
      await aaveWithdrawTrickContract.deployed();

      // Withdraw 1
      const withdrawAmount = units(1);
      // tranfer to the trick contract
      await utils.increaseTime(86400);
      await poolLogicProxy.connect(logicOwner).transfer(aaveWithdrawTrickContract.address, withdrawAmount);

      // await poolLogicProxy.withdraw(withdrawAmount); // Legacy way to withdraw from Aave
      const complexAssetsData = await getComplexAssetsData(deployments, testParams, poolLogicProxy, withdrawAmount);

      for (let i = 0; i < complexAssetsData.length; i++) {
        if (complexAssetsData[i].supportedAsset === testParams.lendingPool) {
          await aaveWithdrawTrickContract.setSwapData(
            complexAssetsData[i].withdrawData,
            poolLogicProxy.address,
            testParams.swapper,
          );
          const modifiedSwapData = await aaveWithdrawTrickContract.mSwapData();
          // modify in place
          complexAssetsData[i].withdrawData = modifiedSwapData;
        }
      }
      const beforeTokenPrice = await poolLogicProxy.tokenPrice();

      // send huge amount debt asset(WETH) to inflate TVL
      await getAccountToken(
        units(1000000),
        aaveWithdrawTrickContract.address,
        WETH.address,
        testParams.assetsBalanceOfSlot.weth,
      );
      const attackerContractWETHBalanceBefore = await WETH.balanceOf(aaveWithdrawTrickContract.address);

      const totalSupplyBefore = await poolLogicProxy.totalSupply();

      const attackerContractPoolTokenBalanceBefore = await poolLogicProxy.balanceOf(aaveWithdrawTrickContract.address);

      await aaveWithdrawTrickContract.attack(withdrawAmount, complexAssetsData, attackType);

      const attackerContractPoolTokenBalanceAfter = await poolLogicProxy.balanceOf(aaveWithdrawTrickContract.address);

      const totalSupplyAfter = await poolLogicProxy.totalSupply();
      console.log("totalSupplyBefore", totalSupplyBefore.toString());
      console.log("totalSupplyAfter", totalSupplyAfter.toString());
      const afterTokenPrice = await poolLogicProxy.tokenPrice();
      const attackerContractWETHBalanceAfter = await WETH.balanceOf(aaveWithdrawTrickContract.address);

      const someUserPoolTokenBalanceAfter = await poolLogicProxy.balanceOf(deployments.user.address);
      console.log("beforeTokenPrice", beforeTokenPrice.toString());
      console.log("afterTokenPrice", afterTokenPrice.toString());
      console.log("attackerContractWETHBalanceBefore", attackerContractWETHBalanceBefore.toString());
      console.log("attackerContractWETHBalanceAfter", attackerContractWETHBalanceAfter.toString());

      console.log("attackerContractPoolTokenBalanceBefore", attackerContractPoolTokenBalanceBefore.toString());
      console.log("attackerContractPoolTokenBalanceAfter", attackerContractPoolTokenBalanceAfter.toString());
      // attacker got back the sent ETH
      checkAlmostSame(attackerContractWETHBalanceAfter, attackerContractWETHBalanceBefore, 0.000001);

      // some user got rekt
      expect(someUserPoolTokenBalanceAfter).to.be.eq(someUserPoolTokenBalanceBefore);
      // token price decreased by 6/11 (almost half)
      expect(afterTokenPrice).to.be.lt(beforeTokenPrice.mul(6).div(11));
    };
    const mintMangerFeeAttack = async () => {
      await baseAttack(0);
    };

    const depositReentranceAttack = async () => {
      await baseAttack(1);
    };

    before(async () => {
      deployments = await deployBackboneContracts(testParams);
      await deployAaveV3TestInfrastructure(deployments, testParams);

      poolFactory = deployments.poolFactory;
      logicOwner = deployments.owner;
      manager = deployments.manager;

      WETH = deployments.assets.WETH;
      USDC = deployments.assets.USDC;

      const funds = await createFund(poolFactory, logicOwner, manager, [{ asset: USDC.address, isDeposit: true }]);
      poolLogicProxy = funds.poolLogicProxy;
      poolManagerLogicProxy = funds.poolManagerLogicProxy;

      await getAccountToken(units(100000, 6), logicOwner.address, USDC.address, testParams.assetsBalanceOfSlot.usdc);

      await USDC.approve(poolLogicProxy.address, units(20000, 6));
      await poolLogicProxy.deposit(USDC.address, units(20000, 6));
    });

    utils.beforeAfterReset(beforeEach, afterEach);

    describe("after deposit into and borrow from aave", async () => {
      beforeEach(async () => {
        // add supported assets
        await poolManagerLogicProxy
          .connect(manager)
          .changeAssets([{ asset: testParams.lendingPool, isDeposit: false }], []);

        const amount = units(10000, 6);

        // approve usdc
        const approveABI = iERC20.encodeFunctionData("approve", [testParams.lendingPool, amount]);
        await poolLogicProxy.connect(manager).execTransaction(USDC.address, approveABI);

        const depositABI = iLendingPool.encodeFunctionData("deposit", [
          USDC.address,
          amount,
          poolLogicProxy.address,
          0,
        ]);

        await poolLogicProxy.connect(manager).execTransaction(testParams.lendingPool, depositABI);

        // borrow 1 WETH
        // add supported assets
        await poolManagerLogicProxy.connect(manager).changeAssets([{ asset: WETH.address, isDeposit: false }], []);

        const amountToBorrow = units(1);
        const borrowABI = iLendingPool.encodeFunctionData("borrow", [
          WETH.address,
          amountToBorrow,
          2,
          0,
          poolLogicProxy.address,
        ]);
        await poolLogicProxy.connect(manager).execTransaction(testParams.lendingPool, borrowABI);
      });

      it("can't inject code to inflate tvl and mint manager fees, with withdrawSafe", async () => {
        try {
          // expect it to revert
          await mintMangerFeeAttack();
        } catch (error: unknown) {
          return;
        }
        expect.fail("The attack should have reverted");
      });

      it("deposit reentrance, with withdrawSafe", async () => {
        // manager made debt asset depositable (not intentional)
        // reentrance attack will be able to mint share and got back the deposited debt asset
        // will be explotable if _depositFor and _withdrawTo has no reentrance protection
        await poolManagerLogicProxy.connect(manager).changeAssets([{ asset: WETH.address, isDeposit: true }], []);
        try {
          // expect it to revert
          await depositReentranceAttack();
        } catch (error: unknown) {
          return;
        }
        expect.fail("The attack should have reverted");
      });
    });
  });
};
