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
  instantRedeemFromStargatePool: withdrawFromStargatePool,
  stakeStargateLpToken,
  unstakeStargateLpToken,
} = stargateTestHelpers;

let Underlying: IERC20, Lp: IERC20;
let logicOwner: SignerWithAddress, manager: SignerWithAddress;
let poolFactory: PoolFactory, poolLogicProxy: PoolLogic, poolManagerLogicProxy: PoolManagerLogic;
let deployments: IDeployments;
let stargatePoolId: number, stargateStakingPoolId: number;
let txConfig: TxConfig;
let underlyingBalanceBefore: BigNumber;

export const testStargateLpContractGuard = (testParams: IStargateLpTestParameters[]) => {
  for (const params of testParams) {
    const { network, chainData, asset, depositAmount, testScope } = params;
    const stargate = chainData.stargate;
    const stakingRewardToken = stargate.stakingRewardToken;

    describe(`Stargate LP contract guard test: ${asset.lpAssetName}`, function () {
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

        // add supported assets
        await poolManagerLogicProxy.connect(manager).changeAssets(
          [
            { asset: stargate.pools[asset.lpAssetName].address, isDeposit: true },
            { asset: stargate.stakingRewardToken, isDeposit: true },
          ],
          [],
        );

        txConfig = {
          poolLogic: poolLogicProxy,
          manager,
          stargate,
        };

        // Deposit
        await getAccountToken(depositAmount, logicOwner.address, asset.address, asset.balanceOfSlot);
        await Underlying.approve(poolLogicProxy.address, depositAmount);
        await poolLogicProxy.deposit(asset.address, depositAmount);

        underlyingBalanceBefore = await Underlying.balanceOf(poolLogicProxy.address);
      });

      it("Shouldn't be able to deposit if lp not enabled", async function () {
        if (testScope === "minimum") this.skip();

        // remove Stargate LP asset
        await poolManagerLogicProxy.connect(manager).changeAssets([], [stargate.pools[asset.lpAssetName].address]);

        // deposit asset into Stargate pool
        const amount = depositAmount;
        await expect(
          addLiquidityToStargatePool(txConfig, amount, Underlying.address, stargatePoolId),
        ).to.be.revertedWith("stargate pool not enabled");
      });

      it("Shouldn't be able to deposit if the recipient is not the pool", async function () {
        if (testScope === "minimum") this.skip();

        // deposit asset into Stargate pool
        const amount = depositAmount;
        await expect(
          addLiquidityToStargatePool(txConfig, amount, Underlying.address, stargatePoolId, logicOwner.address),
        ).to.be.revertedWith("recipient is not pool");
      });

      it("Shouldn't be able to withdraw if underlying is not enabled", async function () {
        if (testScope === "minimum") this.skip();

        // deposit the asset into Stargate pool
        const amountToDeposit = underlyingBalanceBefore;
        await addLiquidityToStargatePool(txConfig, amountToDeposit, Underlying.address, stargatePoolId);

        // remove underlying asset
        await poolManagerLogicProxy.connect(manager).changeAssets([], [asset.address]);

        // try to withdraw
        await expect(
          withdrawFromStargatePool(txConfig, amountToDeposit, Lp.address, stargatePoolId),
        ).to.be.revertedWith("underlying asset not enabled");
      });

      it("Shouldn't be able to stake if wrong Pool Id", async function () {
        if (testScope === "minimum") this.skip();

        // deposit asset into Stargate pool
        const amountToDeposit = underlyingBalanceBefore;
        await addLiquidityToStargatePool(txConfig, amountToDeposit, Underlying.address, stargatePoolId);
        const lpBalanceAfterDeposit = await Lp.balanceOf(poolLogicProxy.address);

        // stake all LP tokens
        const amountToStake = lpBalanceAfterDeposit;
        await expect(
          stakeStargateLpToken(
            txConfig,
            amountToStake,
            Lp.address,
            stargateStakingPoolId > 0 ? stargateStakingPoolId - 1 : stargateStakingPoolId + 1, // shift the poolId to a wrong ID
          ),
        ).to.be.reverted;
      });

      it("Shouldn't be able to stake if unsupported reward token", async function () {
        if (testScope === "minimum") this.skip();

        // deposit asset into Stargate pool
        const amountToDeposit = underlyingBalanceBefore;
        await addLiquidityToStargatePool(txConfig, amountToDeposit, Underlying.address, stargatePoolId);
        const lpBalanceAfterDeposit = await Lp.balanceOf(poolLogicProxy.address);

        // stake all LP tokens
        const amountToStake = lpBalanceAfterDeposit;

        // remove reward token asset
        await poolManagerLogicProxy.connect(manager).changeAssets([], [stargate.stakingRewardToken]);

        // try to stake tokens
        await expect(
          stakeStargateLpToken(txConfig, amountToStake, Lp.address, stargateStakingPoolId),
        ).to.be.revertedWith("unsupported reward token");
      });

      it("Should be able to stake if not valid reward token", async function () {
        if (testScope === "minimum") this.skip();

        // deposit asset into Stargate pool
        const amountToDeposit = underlyingBalanceBefore;
        await addLiquidityToStargatePool(txConfig, amountToDeposit, Underlying.address, stargatePoolId);
        const lpBalanceAfterDeposit = await Lp.balanceOf(poolLogicProxy.address);

        // stake all LP tokens
        const amountToStake = lpBalanceAfterDeposit;

        // remove reward token asset
        await poolManagerLogicProxy.connect(manager).changeAssets([], [stargate.stakingRewardToken]);
        // remove from global supported assets
        deployments.assetHandler.removeAsset(stargate.stakingRewardToken);

        await stakeStargateLpToken(txConfig, amountToStake, Lp.address, stargateStakingPoolId);
      });

      it("Shouldn't be able to unstake if unsupported reward token", async function () {
        if (testScope === "minimum") this.skip();

        // deposit asset into Stargate pool
        const amountToDeposit = underlyingBalanceBefore;
        await addLiquidityToStargatePool(txConfig, amountToDeposit, Underlying.address, stargatePoolId);
        const lpBalanceAfterDeposit = await Lp.balanceOf(poolLogicProxy.address);

        // stake all LP tokens
        const amountToStake = lpBalanceAfterDeposit;
        await stakeStargateLpToken(txConfig, amountToStake, Lp.address, stargateStakingPoolId);

        // NOTE: Can't remove LP asset because there is a balance in the pool

        // remove reward token asset
        await poolManagerLogicProxy.connect(manager).changeAssets([], [stargate.stakingRewardToken]);

        // try to unstake tokens
        await expect(unstakeStargateLpToken(txConfig, amountToStake, stargateStakingPoolId)).to.be.revertedWith(
          "unsupported reward token",
        );
      });

      it(`Deposit, stake, unstake and withdraw ${asset.lpAssetName}`, async function () {
        // Note that the Stargate LP token is 6 decimal places, so there are some rounding errors to account for

        // deposit the asset into Stargate pool
        const amountToDeposit = underlyingBalanceBefore;
        await addLiquidityToStargatePool(txConfig, amountToDeposit, Underlying.address, stargatePoolId);
        const lpBalanceAfterDeposit = await Lp.balanceOf(poolLogicProxy.address);

        // stake all LP tokens
        const amountToStake = lpBalanceAfterDeposit;
        await stakeStargateLpToken(txConfig, amountToStake, Lp.address, stargateStakingPoolId);

        // unstake 50% of LP tokens
        const amountToPartialWithdraw = lpBalanceAfterDeposit.div(2);
        await unstakeStargateLpToken(txConfig, amountToPartialWithdraw, stargateStakingPoolId);

        // remove liquidity of unstaked LP tokens
        await withdrawFromStargatePool(txConfig, amountToPartialWithdraw, Lp.address, stargatePoolId);
        const lpAssetBalanceAfterPartialWithdraw = await poolManagerLogicProxy.assetBalance(Lp.address);

        // unstake and remove remaining liquidity
        const lpBalanceIsOddNumber = lpBalanceAfterDeposit.eq(lpBalanceAfterDeposit.div(2).mul(2)) ? false : true;
        // adjust if the total balance is an odd number to ensure 100% is withdrawn
        const amountToFullWithdraw = lpBalanceAfterDeposit.div(2).add(lpBalanceIsOddNumber ? 1 : 0);
        await unstakeStargateLpToken(txConfig, amountToFullWithdraw, stargateStakingPoolId);
        await withdrawFromStargatePool(txConfig, amountToFullWithdraw, Lp.address, stargatePoolId);
        const lpAssetBalanceAfterFullWithdraw = await poolManagerLogicProxy.assetBalance(Lp.address);

        // Partial Stargate withdrawal assertions
        expect(lpAssetBalanceAfterPartialWithdraw).to.be.gt(0);
        // Full Stargate withdrawal assertions
        expect(lpAssetBalanceAfterFullWithdraw).to.be.equal(0); // all of the LP was liquidated
      });
    });
  }
};
