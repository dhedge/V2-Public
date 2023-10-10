import { ethers } from "hardhat";
import { expect } from "chai";
import { BigNumber } from "ethers";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";

import { IERC20, PoolFactory, PoolLogic, PoolManagerLogic } from "../../../../types";
import { createFund } from "../../utils/createFund";
import { getAccountToken } from "../../utils/getAccountTokens";
import { deployContracts, IDeployments } from "../../utils/deployContracts/deployContracts";
import { utils } from "../../utils/utils";
import { stargateTestHelpers, IStargateLpTestParameters, TxConfig } from "./StargateTestHelpers";

const {
  setup,
  addLiquidityToStargatePool,
  instantRedeemFromStargatePool,
  stakeStargateLpToken,
  unstakeStargateLpToken,
} = stargateTestHelpers;

let Underlying: IERC20, Lp: IERC20;
let logicOwner: SignerWithAddress, manager: SignerWithAddress;
let poolFactory: PoolFactory, poolLogicProxy: PoolLogic, poolManagerLogicProxy: PoolManagerLogic;
let deployments: IDeployments;
let stargatePoolId: number, stargateStakingPoolId: number;
let txConfig: TxConfig;
let underlyingBalanceBefore: BigNumber, lpBalanceBefore: BigNumber, poolAssetBalanceBefore: BigNumber;
let tokenPriceBefore: BigNumber;

export const testStargateLpAssetGuard = (testParams: IStargateLpTestParameters[]) => {
  for (const params of testParams) {
    const { network, chainData, asset, depositAmount, testScope } = params;
    const stargate = chainData.stargate;
    const stakingRewardToken = stargate.stakingRewardToken;

    describe(`Stargate LP asset guard test: ${asset.lpAssetName}`, function () {
      utils.beforeAfterReset(before, after);
      utils.beforeAfterReset(beforeEach, afterEach);

      before(async function () {
        [logicOwner, manager] = await ethers.getSigners();

        deployments = await deployContracts(network);
        poolFactory = deployments.poolFactory;

        await setup(deployments, chainData, stakingRewardToken); // deploy test contracts

        Underlying = <IERC20>(
          await ethers.getContractAt("@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20", asset.address)
        );
        Lp = <IERC20>(
          await ethers.getContractAt(
            "@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20",
            stargate.pools[asset.lpAssetName].address,
          )
        );

        stargatePoolId = stargate.pools[asset.lpAssetName].poolId;
        stargateStakingPoolId = stargate.pools[asset.lpAssetName].stakingPoolId;

        const funds = await createFund(poolFactory, logicOwner, manager, [{ asset: asset.address, isDeposit: true }], {
          performance: BigNumber.from(0),
          management: BigNumber.from(0),
        });
        poolLogicProxy = funds.poolLogicProxy;
        poolManagerLogicProxy = funds.poolManagerLogicProxy;
        txConfig = {
          poolLogic: poolLogicProxy,
          manager,
          stargate,
        };

        // add supported assets
        await poolManagerLogicProxy.connect(manager).changeAssets(
          [
            { asset: stargate.pools[asset.lpAssetName].address, isDeposit: false },
            { asset: stargate.stakingRewardToken, isDeposit: false },
          ],
          [],
        );

        // Deposit
        await getAccountToken(depositAmount, logicOwner.address, asset.address, asset.balanceOfSlot);
        await Underlying.approve(poolLogicProxy.address, depositAmount);
        await poolLogicProxy.deposit(asset.address, depositAmount);

        underlyingBalanceBefore = await Underlying.balanceOf(poolLogicProxy.address);
        lpBalanceBefore = await Lp.balanceOf(poolLogicProxy.address);
        poolAssetBalanceBefore = await poolManagerLogicProxy.assetBalance(Lp.address);
        tokenPriceBefore = await poolLogicProxy.tokenPrice();
      });

      it(`Deposit and receive ${asset.lpAssetName} LP`, async function () {
        // deposit aasset into Stargate pool
        const amount = underlyingBalanceBefore;
        await addLiquidityToStargatePool(txConfig, amount, Underlying.address, stargatePoolId);

        const underlyingBalanceAfterDeposit = await Underlying.balanceOf(poolLogicProxy.address);
        const lpBalanceAfterDeposit = await Lp.balanceOf(poolLogicProxy.address);
        const tokenPriceAfterDeposit = await poolLogicProxy.tokenPrice();
        const poolAssetBalanceAfterDeposit = await poolManagerLogicProxy.assetBalance(Lp.address);
        const lpAssetBalanceAfterDeposit = await poolManagerLogicProxy.assetBalance(Lp.address);

        expect(underlyingBalanceBefore).to.be.equal(depositAmount);
        expect(underlyingBalanceAfterDeposit).to.be.equal(0);
        expect(lpBalanceBefore).to.be.equal(0);
        expect(lpBalanceAfterDeposit).to.be.gt(0);
        expect(poolAssetBalanceBefore).to.be.eq(0);
        expect(poolAssetBalanceAfterDeposit).to.be.gt(0);
        expect(lpAssetBalanceAfterDeposit).to.be.closeTo(depositAmount, lpAssetBalanceAfterDeposit.div(100_000));
        expect(tokenPriceBefore).to.be.closeTo(tokenPriceAfterDeposit, tokenPriceBefore.div(10000));
      });

      it(`Stake ${asset.lpAssetName}`, async function () {
        // deposit asset into Stargate pool
        const amountToDeposit = underlyingBalanceBefore;
        await addLiquidityToStargatePool(txConfig, amountToDeposit, Underlying.address, stargatePoolId);

        const underlyingBalanceAfterDeposit = await Underlying.balanceOf(poolLogicProxy.address);
        const lpBalanceAfterDeposit = await Lp.balanceOf(poolLogicProxy.address);
        const lpAssetBalanceAfterDeposit = await poolManagerLogicProxy.assetBalance(Lp.address);

        // stake all LP tokens
        const amountToStake = lpBalanceAfterDeposit;
        await stakeStargateLpToken(txConfig, amountToStake, Lp.address, stargateStakingPoolId);
        const underlyingBalanceAfterStake = await Underlying.balanceOf(poolLogicProxy.address);
        const lpBalanceAfterStake = await Lp.balanceOf(poolLogicProxy.address);
        const tokenPriceAfterStake = await poolLogicProxy.tokenPrice();
        const lpAssetBalanceAfterStake = await poolManagerLogicProxy.assetBalance(Lp.address);

        expect(lpAssetBalanceAfterDeposit).to.be.equal(lpAssetBalanceAfterStake);
        expect(underlyingBalanceAfterDeposit).to.be.equal(0);
        expect(lpBalanceAfterDeposit).to.be.gt(0);
        expect(underlyingBalanceAfterStake).to.be.eq(0);
        expect(lpBalanceAfterStake).to.be.eq(0); // LP tokens transferred to staking contract
        expect(lpAssetBalanceAfterDeposit).to.be.gt(0);
        expect(lpAssetBalanceAfterDeposit).to.be.eq(lpAssetBalanceAfterStake);
        expect(tokenPriceBefore).to.be.closeTo(tokenPriceAfterStake, tokenPriceBefore.div(10000));
      });

      it(`Unstake ${asset.lpAssetName}`, async function () {
        if (testScope === "minimum") this.skip();

        // deposit asset into Stargate pool
        const amountToDeposit = underlyingBalanceBefore;
        await addLiquidityToStargatePool(txConfig, amountToDeposit, Underlying.address, stargatePoolId);
        const lpBalanceAfterDeposit = await Lp.balanceOf(poolLogicProxy.address);

        // stake all LP tokens
        const amountToStake = lpBalanceAfterDeposit;
        await stakeStargateLpToken(txConfig, amountToStake, Lp.address, stargateStakingPoolId);
        const tokenPriceAfterStake = await poolLogicProxy.tokenPrice();

        // unstake 50% of LP tokens
        const amountToUnstake = lpBalanceAfterDeposit.div(2);
        await unstakeStargateLpToken(txConfig, amountToUnstake, stargateStakingPoolId);
        const tokenPriceAfterUnstake = await poolLogicProxy.tokenPrice();
        const underlyingBalanceAfterUnstake = await Underlying.balanceOf(poolLogicProxy.address);
        const lpBalanceAfterUnstake = await Lp.balanceOf(poolLogicProxy.address);

        expect(underlyingBalanceAfterUnstake).to.be.equal(0);
        expect(lpBalanceAfterUnstake).to.be.gt(0); // LP token is back in the pool after unstaking
        expect(tokenPriceAfterStake).to.be.closeTo(tokenPriceAfterUnstake, tokenPriceAfterStake.div(10000));
      });

      it(`Withdraw ${asset.lpAssetName}`, async function () {
        // Note that the Stargate LP token is 6 decimal places, so there are some rounding errors to account for

        // deposit the asset into Stargate pool
        const amountToDeposit = underlyingBalanceBefore;
        await addLiquidityToStargatePool(txConfig, amountToDeposit, Underlying.address, stargatePoolId);
        const lpBalanceAfterDeposit = await Lp.balanceOf(poolLogicProxy.address);
        const lpAssetBalanceAfterDeposit = await poolManagerLogicProxy.assetBalance(Lp.address);

        // stake all LP tokens
        const amountToStake = lpBalanceAfterDeposit;
        await stakeStargateLpToken(txConfig, amountToStake, Lp.address, stargateStakingPoolId);

        // unstake 50% of LP tokens
        const amountToPartialWithdraw = lpBalanceAfterDeposit.div(2);
        await unstakeStargateLpToken(txConfig, amountToPartialWithdraw, stargateStakingPoolId);
        const tokenPriceAfterPartialUnstake = await poolLogicProxy.tokenPrice();

        // remove liquidity of unstaked LP tokens
        await instantRedeemFromStargatePool(txConfig, amountToPartialWithdraw, Lp.address, stargatePoolId);
        const tokenPriceAfterPartialWithdraw = await poolLogicProxy.tokenPrice();
        const underlyingBalanceAfterPartialWithdraw = await Underlying.balanceOf(poolLogicProxy.address);
        const lpAssetBalanceAfterPartialWithdraw = await poolManagerLogicProxy.assetBalance(Lp.address);

        // unstake and remove remaining liquidity
        const lpBalanceIsOddNumber = lpBalanceAfterDeposit.eq(lpBalanceAfterDeposit.div(2).mul(2)) ? false : true;
        // adjust if the total balance is an odd number to ensure 100% is withdrawn
        const amountToFullWithdraw = lpBalanceAfterDeposit.div(2).add(lpBalanceIsOddNumber ? 1 : 0);
        await unstakeStargateLpToken(txConfig, amountToFullWithdraw, stargateStakingPoolId);
        await instantRedeemFromStargatePool(txConfig, amountToFullWithdraw, Lp.address, stargatePoolId);
        const tokenPriceAfterFullWithdraw = await poolLogicProxy.tokenPrice();
        const underlyingBalanceAfterFullWithdraw = await Underlying.balanceOf(poolLogicProxy.address);
        const lpAssetBalanceAfterFullWithdraw = await poolManagerLogicProxy.assetBalance(Lp.address);

        // Partial Stargate withdrawal assertions
        // check that half of the LP was liquidated
        expect(underlyingBalanceAfterPartialWithdraw).to.be.closeTo(
          underlyingBalanceBefore.div(2),
          underlyingBalanceAfterPartialWithdraw.div(10000), // if initial balance is an odd number, there may be some slight difference
        );
        expect(lpAssetBalanceAfterPartialWithdraw).to.be.closeTo(
          lpAssetBalanceAfterDeposit.div(2),
          lpAssetBalanceAfterPartialWithdraw.div(10000),
        );
        expect(tokenPriceAfterPartialUnstake).to.be.closeTo(
          tokenPriceAfterPartialWithdraw,
          tokenPriceAfterPartialUnstake.div(10000),
        );
        // Full Stargate withdrawal assertions
        expect(underlyingBalanceAfterFullWithdraw).to.be.closeTo(
          underlyingBalanceBefore,
          underlyingBalanceAfterFullWithdraw.div(10000), // the LP is 6 decimal places so there will be some rounding error
        );
        expect(lpAssetBalanceAfterFullWithdraw).to.be.equal(0); // all of the LP was liquidated
        expect(tokenPriceAfterPartialWithdraw).to.be.closeTo(
          tokenPriceAfterFullWithdraw,
          tokenPriceAfterPartialWithdraw.div(10000),
        );
      });

      it(`Withdraw from dHedge pool after staking ${asset.lpAssetName}`, async function () {
        // deposit asset into Stargate pool
        const amountToDeposit = underlyingBalanceBefore;
        await addLiquidityToStargatePool(txConfig, amountToDeposit, Underlying.address, stargatePoolId);
        const lpAssetBalanceAfterDeposit = await poolManagerLogicProxy.assetBalance(Lp.address);
        const lpBalanceAfterDeposit = await Lp.balanceOf(poolLogicProxy.address);
        const tokenPriceAfterDeposit = await poolLogicProxy.tokenPrice();

        // stake 50% of LP tokens
        const amountToStake = lpBalanceAfterDeposit.div(2);
        await stakeStargateLpToken(txConfig, amountToStake, Lp.address, stargateStakingPoolId);

        // withdraw 50% from the dHedge pool
        await ethers.provider.send("evm_increaseTime", [60 * 60 * 24]); // 24h pool cooldown
        const poolTokenBalance = await poolLogicProxy.balanceOf(logicOwner.address);
        await poolLogicProxy.withdraw(poolTokenBalance.div(2));
        const lpAssetBalanceAfterHalfWithdrawal = await poolManagerLogicProxy.assetBalance(Lp.address);
        const tokenPriceAfterHalfWithdrawal = await poolLogicProxy.tokenPrice();
        const userLpBalanceAfterHalfWithdrawal = await Lp.balanceOf(logicOwner.address);

        // withdraw remaining 50%
        const poolTokenBalanceAfterHalfWithdraw = await poolLogicProxy.balanceOf(logicOwner.address);
        await poolLogicProxy.withdraw(poolTokenBalanceAfterHalfWithdraw);
        const userLpBalanceAfterFullWithdrawal = await Lp.balanceOf(logicOwner.address);
        const lpAssetBalanceAfterFullWithdrawal = await poolManagerLogicProxy.assetBalance(Lp.address);

        // 50% half withdrawal assertions
        expect(lpAssetBalanceAfterDeposit.div(2)).is.closeTo(
          lpAssetBalanceAfterHalfWithdrawal,
          lpAssetBalanceAfterDeposit.div(10000), // if initial balance is an odd number, there may be some slight difference
        );
        expect(lpBalanceAfterDeposit.div(2)).is.closeTo(userLpBalanceAfterHalfWithdrawal, 1);
        expect(tokenPriceAfterDeposit).is.closeTo(tokenPriceAfterHalfWithdrawal, tokenPriceAfterDeposit.div(10000));
        // 100% full withdrawal assertions
        expect(userLpBalanceAfterFullWithdrawal).to.be.equal(lpBalanceAfterDeposit);
        expect(lpAssetBalanceAfterFullWithdrawal).to.be.equal(0);
      });
    });
  }
};
