import { ethers } from "hardhat";
import { expect } from "chai";
import { checkAlmostSame, getAmountOut, units } from "../../testHelpers";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import {
  AssetHandler,
  IERC20,
  IERC20__factory,
  IMiniChefV2__factory,
  IUniswapV2Router__factory,
  PoolFactory,
  PoolLogic,
  PoolManagerLogic,
  SushiMiniChefV2Guard,
} from "../../../types";
import { createFund } from "../utils/createFund";
import { polygonChainData } from "../../../config/chainData/polygonData";
const { assets, assetsBalanceOfSlot, sushi } = polygonChainData;
import { BigNumber } from "ethers";
import { getAccountToken } from "../utils/getAccountTokens";
import { deployContracts } from "../utils/deployContracts/deployContracts";

describe("Sushiswap V2 Test", function () {
  let WMATIC: IERC20, WETH: IERC20, USDC: IERC20, SushiLPUSDCWETH: IERC20, SUSHI: IERC20;
  let logicOwner: SignerWithAddress, manager: SignerWithAddress, user: SignerWithAddress;
  let poolFactory: PoolFactory,
    poolLogicProxy: PoolLogic,
    poolManagerLogicProxy: PoolManagerLogic,
    sushiMiniChefV2Guard: SushiMiniChefV2Guard,
    assetHandler: AssetHandler;
  let availableLpToken: BigNumber;
  const iERC20 = new ethers.utils.Interface(IERC20__factory.abi);
  const iMiniChefV2 = new ethers.utils.Interface(IMiniChefV2__factory.abi);
  const iSushiswapV2Router = new ethers.utils.Interface(IUniswapV2Router__factory.abi);
  const iUniswapV2Router = new ethers.utils.Interface(IUniswapV2Router__factory.abi);

  before(async function () {
    [logicOwner, manager, , user] = await ethers.getSigners();

    const deployments = await deployContracts("polygon");
    poolFactory = deployments.poolFactory;
    assetHandler = deployments.assetHandler;
    // eslint-disable-next-line @typescript-eslint/no-non-null-assertion
    sushiMiniChefV2Guard = deployments.sushiMiniChefV2Guard!;
    USDC = deployments.assets.USDC;
    // eslint-disable-next-line @typescript-eslint/no-non-null-assertion
    SUSHI = deployments.assets.SUSHI!;
    // eslint-disable-next-line @typescript-eslint/no-non-null-assertion
    WETH = deployments.assets.WETH;
    // eslint-disable-next-line @typescript-eslint/no-non-null-assertion
    WMATIC = deployments.assets.WMATIC!;
    // eslint-disable-next-line @typescript-eslint/no-non-null-assertion
    SushiLPUSDCWETH = deployments.assets.SushiLPUSDCWETH!;

    await getAccountToken(units(10000, 6), logicOwner.address, assets.usdc, assetsBalanceOfSlot.usdc);

    const funds = await createFund(poolFactory, logicOwner, manager, [
      { asset: assets.usdc, isDeposit: true },
      { asset: assets.weth, isDeposit: true },
    ]);
    poolLogicProxy = funds.poolLogicProxy;
    poolManagerLogicProxy = funds.poolManagerLogicProxy;

    // Deposit 200 USDC
    await USDC.approve(poolLogicProxy.address, units(200, 6));
    await poolLogicProxy.deposit(assets.usdc, units(200, 6));
  });

  it("Should be able to approve", async () => {
    let approveABI = iERC20.encodeFunctionData("approve", [assets.usdc, (200e6).toString()]);
    await expect(poolLogicProxy.connect(manager).execTransaction(assets.usdt, approveABI)).to.be.revertedWith(
      "asset not enabled in pool",
    );

    await expect(poolLogicProxy.connect(manager).execTransaction(assets.usdc, approveABI)).to.be.revertedWith(
      "unsupported spender approval",
    );

    approveABI = iERC20.encodeFunctionData("approve", [sushi.router, (200e6).toString()]);
    await poolLogicProxy.connect(manager).execTransaction(assets.usdc, approveABI);
  });

  it("should be able to swap tokens on sushiswap.", async () => {
    const sourceAmount = (100e6).toString();
    let swapABI = iSushiswapV2Router.encodeFunctionData("swapExactTokensForTokens", [
      sourceAmount,
      0,
      [assets.usdc, assets.weth],
      poolManagerLogicProxy.address,
      0,
    ]);

    await expect(
      poolLogicProxy.connect(manager).execTransaction("0x0000000000000000000000000000000000000000", swapABI),
    ).to.be.revertedWith("non-zero address is required");

    swapABI = iSushiswapV2Router.encodeFunctionData("swapExactTokensForTokens", [
      sourceAmount,
      0,
      [assets.usdt, assets.weth],
      poolLogicProxy.address,
      0,
    ]);
    await expect(poolLogicProxy.connect(manager).execTransaction(assets.usdc, swapABI)).to.be.revertedWith(
      "invalid transaction",
    );

    swapABI = iSushiswapV2Router.encodeFunctionData("swapExactTokensForTokens", [
      sourceAmount,
      0,
      [assets.usdc, assets.weth, assets.usdt],
      poolLogicProxy.address,
      0,
    ]);
    await expect(poolLogicProxy.connect(manager).execTransaction(sushi.router, swapABI)).to.be.revertedWith(
      "unsupported destination asset",
    );

    swapABI = iSushiswapV2Router.encodeFunctionData("swapExactTokensForTokens", [
      sourceAmount,
      0,
      [assets.usdc, assets.weth],
      user.address,
      0,
    ]);
    await expect(poolLogicProxy.connect(manager).execTransaction(sushi.router, swapABI)).to.be.revertedWith(
      "recipient is not pool",
    );

    swapABI = iSushiswapV2Router.encodeFunctionData("swapExactTokensForTokens", [
      sourceAmount,
      await getAmountOut(sushi.router, sourceAmount, [assets.usdc, assets.weth]),
      [assets.usdc, assets.weth],
      poolLogicProxy.address,
      0,
    ]);
    await expect(poolLogicProxy.connect(manager).execTransaction(sushi.router, swapABI)).to.be.revertedWith(
      "UniswapV2Router: EXPIRED",
    );

    swapABI = iSushiswapV2Router.encodeFunctionData("swapExactTokensForTokens", [
      sourceAmount,
      await getAmountOut(sushi.router, sourceAmount, [assets.usdc, assets.weth]),
      [assets.usdc, assets.weth],
      poolLogicProxy.address,
      Math.floor(Date.now() / 1000 + 100000000),
    ]);
    await poolLogicProxy.connect(manager).execTransaction(sushi.router, swapABI);

    expect(await USDC.balanceOf(poolLogicProxy.address)).to.be.equal(100e6);
  });

  it("should be able to withdraw", async function () {
    // Withdraw 50%
    const withdrawAmount = units(100);

    await ethers.provider.send("evm_increaseTime", [86400]);

    await poolLogicProxy.withdraw(withdrawAmount);
  });

  describe("Staking", () => {
    const stakeAvailableLpTokens = async () => {
      availableLpToken = await SushiLPUSDCWETH.balanceOf(poolLogicProxy.address);

      const depositAbi = iMiniChefV2.encodeFunctionData("deposit", [
        sushi.pools.usdc_weth.poolId,
        availableLpToken,
        poolLogicProxy.address,
      ]);

      const approveABI = iERC20.encodeFunctionData("approve", [sushi.minichef, availableLpToken]);
      await poolLogicProxy.connect(manager).execTransaction(sushi.pools.usdc_weth.address, approveABI);
      await poolLogicProxy.connect(manager).execTransaction(sushi.minichef, depositAbi);
    };

    it("manager can add liquidity", async () => {
      await poolManagerLogicProxy
        .connect(manager)
        .changeAssets([{ asset: sushi.pools.usdc_weth.address, isDeposit: false }], []);

      const tokenA = assets.usdc;
      const tokenB = assets.weth;
      const amountADesired = await USDC.balanceOf(poolLogicProxy.address);
      const amountBDesired = await WETH.balanceOf(poolLogicProxy.address);
      const addLiquidityAbi = iUniswapV2Router.encodeFunctionData("addLiquidity", [
        tokenA,
        tokenB,
        amountADesired,
        amountBDesired,
        0,
        0,
        poolLogicProxy.address,
        Math.floor(Date.now() / 1000 + 100000000),
      ]);

      let approveABI = iERC20.encodeFunctionData("approve", [sushi.router, amountADesired]);
      await poolLogicProxy.connect(manager).execTransaction(assets.usdc, approveABI);
      approveABI = iERC20.encodeFunctionData("approve", [sushi.router, amountBDesired]);
      await poolLogicProxy.connect(manager).execTransaction(assets.weth, approveABI);

      const lpBalanceBefore = await SushiLPUSDCWETH.balanceOf(poolLogicProxy.address);
      const usdcBalanceBefore = await USDC.balanceOf(poolLogicProxy.address);
      const wethBalanceBefore = await WETH.balanceOf(poolLogicProxy.address);
      const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

      expect(lpBalanceBefore).to.be.equal(0);

      await poolLogicProxy.connect(manager).execTransaction(sushi.router, addLiquidityAbi);

      expect(await SushiLPUSDCWETH.balanceOf(poolLogicProxy.address)).to.be.gt(lpBalanceBefore);
      expect(await USDC.balanceOf(poolLogicProxy.address)).to.be.lt(usdcBalanceBefore);
      expect(await WETH.balanceOf(poolLogicProxy.address)).to.be.lt(wethBalanceBefore);
      checkAlmostSame(await poolManagerLogicProxy.totalFundValue(), totalFundValueBefore);
    });

    it("manager can Stake Sushi LP token", async () => {
      const stakeEvent = new Promise((resolve, reject) => {
        sushiMiniChefV2Guard.on("Stake", (fundAddress, asset, stakingContract, amount, time, event) => {
          event.removeListener();

          resolve({
            fundAddress,
            asset,
            stakingContract,
            amount,
            time,
          });
        });

        setTimeout(() => {
          reject(new Error("timeout"));
        }, 60000);
      });

      availableLpToken = await SushiLPUSDCWETH.balanceOf(poolLogicProxy.address);

      const depositAbi = iMiniChefV2.encodeFunctionData("deposit", [
        sushi.pools.usdc_weth.poolId,
        availableLpToken,
        poolLogicProxy.address,
      ]);

      const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

      const sushiLPPrice = await assetHandler.getUSDPrice(sushi.pools.usdc_weth.address);
      expect(totalFundValueBefore).to.gte(
        sushiLPPrice.mul(availableLpToken).div(ethers.BigNumber.from((1e18).toString())),
      ); // should at least account for the staked tokens

      // attempt to deposit with manager as recipient
      const badDepositAbi = iMiniChefV2.encodeFunctionData("deposit", [
        sushi.pools.usdc_weth.poolId,
        availableLpToken,
        manager.address,
      ]);

      await expect(poolLogicProxy.connect(manager).execTransaction(sushi.minichef, badDepositAbi)).to.be.revertedWith(
        "recipient is not pool",
      );

      await expect(poolLogicProxy.connect(manager).execTransaction(sushi.minichef, depositAbi)).to.be.revertedWith(
        "enable reward token",
      );

      // enable SUSHI token in pool
      await poolManagerLogicProxy.connect(manager).changeAssets([{ asset: assets.sushi, isDeposit: false }], []);

      await expect(poolLogicProxy.connect(manager).execTransaction(sushi.minichef, depositAbi)).to.be.revertedWith(
        "enable reward token",
      );

      // enable WMATIC token in pool
      await poolManagerLogicProxy.connect(manager).changeAssets([{ asset: assets.wmatic, isDeposit: false }], []);

      const approveABI = iERC20.encodeFunctionData("approve", [sushi.minichef, availableLpToken]);
      await poolLogicProxy.connect(manager).execTransaction(sushi.pools.usdc_weth.address, approveABI);

      await poolLogicProxy.connect(manager).execTransaction(sushi.minichef, depositAbi);

      expect(await poolManagerLogicProxy.assetBalance(sushi.pools.usdc_weth.address)).to.be.equal(availableLpToken);
      checkAlmostSame(await poolManagerLogicProxy.totalFundValue(), totalFundValueBefore);

      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const event: any = await stakeEvent;
      expect(event.fundAddress).to.equal(poolLogicProxy.address);
      expect(event.asset).to.equal(sushi.pools.usdc_weth.address);
      expect(event.stakingContract).to.equal(sushi.minichef);
      expect(event.amount).to.equal(availableLpToken);
    });

    it("manager can Unstake Sushi LP token", async function () {
      const unstakeEvent = new Promise((resolve, reject) => {
        sushiMiniChefV2Guard.on("Unstake", (fundAddress, asset, stakingContract, amount, time, event) => {
          event.removeListener();

          resolve({
            fundAddress,
            asset,
            stakingContract,
            amount,
            time,
          });
        });

        setTimeout(() => {
          reject(new Error("timeout"));
        }, 60000);
      });

      // attempt to withdraw with manager as recipient
      const badWithdrawAbi = iMiniChefV2.encodeFunctionData("withdraw", [
        sushi.pools.usdc_weth.poolId,
        availableLpToken,
        manager.address,
      ]);

      await expect(poolLogicProxy.connect(manager).execTransaction(sushi.minichef, badWithdrawAbi)).to.be.revertedWith(
        "recipient is not pool",
      );

      const withdrawAbi = iMiniChefV2.encodeFunctionData("withdraw", [
        sushi.pools.usdc_weth.poolId,
        availableLpToken,
        poolLogicProxy.address,
      ]);

      const wmaticBalanceBefore = await WMATIC.balanceOf(poolLogicProxy.address);
      const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

      await poolLogicProxy.connect(manager).execTransaction(sushi.minichef, withdrawAbi);

      expect(await poolManagerLogicProxy.assetBalance(sushi.pools.usdc_weth.address)).to.be.equal(availableLpToken);
      expect(await WMATIC.balanceOf(poolLogicProxy.address)).to.be.gt(wmaticBalanceBefore);
      checkAlmostSame(await poolManagerLogicProxy.totalFundValue(), totalFundValueBefore);

      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const event: any = await unstakeEvent;
      expect(event.fundAddress).to.equal(poolLogicProxy.address);
      expect(event.asset).to.equal(sushi.pools.usdc_weth.address);
      expect(event.stakingContract).to.equal(sushi.minichef);
      expect(event.amount).to.equal(availableLpToken);
    });

    it("manager can Harvest staked Sushi LP token", async function () {
      const claimEvent = new Promise((resolve, reject) => {
        sushiMiniChefV2Guard.on("Claim", (fundAddress, stakingContract, time, event) => {
          event.removeListener();

          resolve({
            fundAddress,
            stakingContract,
            time,
          });
        });

        setTimeout(() => {
          reject(new Error("timeout"));
        }, 60000);
      });

      const harvestAbi = iMiniChefV2.encodeFunctionData("harvest", [
        sushi.pools.usdc_weth.poolId,
        poolLogicProxy.address,
      ]);

      // attempt to harvest with manager as recipient
      const badHarvestAbi = iMiniChefV2.encodeFunctionData("withdraw", [
        sushi.pools.usdc_weth.poolId,
        availableLpToken,
        manager.address,
      ]);

      await expect(poolLogicProxy.connect(manager).execTransaction(sushi.minichef, badHarvestAbi)).to.be.revertedWith(
        "recipient is not pool",
      );

      expect(await SUSHI.balanceOf(poolLogicProxy.address)).to.be.equal(0);

      await poolLogicProxy.connect(manager).execTransaction(sushi.minichef, harvestAbi);

      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const event: any = await claimEvent;
      expect(event.fundAddress).to.equal(poolLogicProxy.address);
      expect(event.stakingContract).to.equal(sushi.minichef);

      expect(await SUSHI.balanceOf(poolLogicProxy.address)).to.be.gt(0);
    });

    it("manager can Emergency Unstake Sushi LP token", async function () {
      const unstakeEvent = new Promise((resolve, reject) => {
        sushiMiniChefV2Guard.on("Unstake", (fundAddress, asset, stakingContract, amount, time, event) => {
          event.removeListener();

          resolve({
            fundAddress,
            asset,
            stakingContract,
            amount,
            time,
          });
        });

        setTimeout(() => {
          reject(new Error("timeout"));
        }, 60000);
      });

      // First stake
      const depositAbi = iMiniChefV2.encodeFunctionData("deposit", [
        sushi.pools.usdc_weth.poolId,
        availableLpToken,
        poolLogicProxy.address,
      ]);
      const approveABI = iERC20.encodeFunctionData("approve", [sushi.minichef, availableLpToken]);
      await poolLogicProxy.connect(manager).execTransaction(sushi.pools.usdc_weth.address, approveABI);
      await poolLogicProxy.connect(manager).execTransaction(sushi.minichef, depositAbi);

      // Then emergency unstake
      // attempt to withdraw with manager as recipient
      const badEmergencyWithdrawAbi = iMiniChefV2.encodeFunctionData("emergencyWithdraw", [
        sushi.pools.usdc_weth.poolId,
        manager.address,
      ]);
      await expect(
        poolLogicProxy.connect(manager).execTransaction(sushi.minichef, badEmergencyWithdrawAbi),
      ).to.be.revertedWith("recipient is not pool");

      const emergencyWithdrawAbi = iMiniChefV2.encodeFunctionData("emergencyWithdraw", [
        sushi.pools.usdc_weth.poolId,
        poolLogicProxy.address,
      ]);

      const wmaticBalanceBefore = await WMATIC.balanceOf(poolLogicProxy.address);
      const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

      await poolLogicProxy.connect(manager).execTransaction(sushi.minichef, emergencyWithdrawAbi);

      expect(await poolManagerLogicProxy.assetBalance(sushi.pools.usdc_weth.address)).to.be.equal(availableLpToken);
      expect(await WMATIC.balanceOf(poolLogicProxy.address)).to.be.gt(wmaticBalanceBefore);
      checkAlmostSame(await poolManagerLogicProxy.totalFundValue(), totalFundValueBefore);

      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const event: any = await unstakeEvent;
      expect(event.fundAddress).to.equal(poolLogicProxy.address);
      expect(event.asset).to.equal(sushi.pools.usdc_weth.address);
      expect(event.stakingContract).to.equal(sushi.minichef);
      expect(event.amount).to.equal(availableLpToken);
    });

    it.skip("manager can Withdraw And Harvest staked Sushi LP token", async function () {
      await stakeAvailableLpTokens();

      const unstakeEvent = new Promise((resolve, reject) => {
        sushiMiniChefV2Guard.on("Unstake", (fundAddress, asset, stakingContract, amount, time, event) => {
          event.removeListener();

          resolve({
            fundAddress,
            asset,
            stakingContract,
            amount,
            time,
          });
        });

        setTimeout(() => {
          reject(new Error("timeout"));
        }, 60000);
      });

      const claimEvent = new Promise((resolve, reject) => {
        sushiMiniChefV2Guard.on("Claim", (fundAddress, stakingContract, time, event) => {
          event.removeListener();

          resolve({
            fundAddress,
            stakingContract,
            time,
          });
        });

        setTimeout(() => {
          reject(new Error("timeout"));
        }, 60000);
      });

      // manager attempts to withdraw to themselves
      let badWithdrawAndHarvestAbi = iMiniChefV2.encodeFunctionData("withdrawAndHarvest", [
        sushi.pools.usdc_weth.poolId,
        availableLpToken,
        manager.address,
      ]);

      await expect(
        poolLogicProxy.connect(manager).execTransaction(sushi.minichef, badWithdrawAndHarvestAbi),
      ).to.be.revertedWith("recipient is not pool");

      // manager attempts to withdraw unknown LP token
      badWithdrawAndHarvestAbi = iMiniChefV2.encodeFunctionData("withdrawAndHarvest", [
        0,
        availableLpToken,
        poolLogicProxy.address,
      ]);

      await expect(
        poolLogicProxy.connect(manager).execTransaction(sushi.minichef, badWithdrawAndHarvestAbi),
      ).to.be.revertedWith("unsupported lp asset");

      const withdrawAndHarvestAbi = iMiniChefV2.encodeFunctionData("withdrawAndHarvest", [
        sushi.pools.usdc_weth.poolId,
        availableLpToken,
        poolLogicProxy.address,
      ]);

      const sushiBalanceBefore = await SUSHI.balanceOf(poolLogicProxy.address);
      const wmaticBalanceBefore = await WMATIC.balanceOf(poolLogicProxy.address);
      const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

      await ethers.provider.send("evm_increaseTime", [3600 * 24]);
      await poolLogicProxy.connect(manager).execTransaction(sushi.minichef, withdrawAndHarvestAbi);

      expect(await SUSHI.balanceOf(poolLogicProxy.address)).to.be.gt(sushiBalanceBefore);
      expect(await WMATIC.balanceOf(poolLogicProxy.address)).to.be.gt(wmaticBalanceBefore);
      expect(await poolManagerLogicProxy.totalFundValue()).to.be.gt(totalFundValueBefore);

      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const eventUnstake: any = await unstakeEvent;
      expect(eventUnstake.fundAddress).to.equal(poolLogicProxy.address);
      expect(eventUnstake.asset).to.equal(sushi.pools.usdc_weth.address);
      expect(eventUnstake.stakingContract).to.equal(sushi.minichef);
      expect(eventUnstake.amount).to.equal(availableLpToken);

      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const eventClaim: any = await claimEvent;
      expect(eventClaim.fundAddress).to.equal(poolLogicProxy.address);
      expect(eventClaim.stakingContract).to.equal(sushi.minichef);
    });

    it.skip("investor can Withdraw staked Sushi LP token", async function () {
      await stakeAvailableLpTokens();

      const withdrawalEvent = new Promise((resolve, reject) => {
        poolLogicProxy.on(
          "Withdrawal",
          (
            fundAddress,
            investor,
            valueWithdrawn,
            fundTokensWithdrawn,
            totalInvestorFundTokens,
            fundValue,
            totalSupply,
            withdrawnAssets,
            time,
            event,
          ) => {
            event.removeListener();

            resolve({
              fundAddress: fundAddress,
              investor: investor,
              valueWithdrawn: valueWithdrawn,
              fundTokensWithdrawn: fundTokensWithdrawn,
              totalInvestorFundTokens: totalInvestorFundTokens,
              fundValue: fundValue,
              totalSupply: totalSupply,
              withdrawnAssets: withdrawnAssets,
              time: time,
            });
          },
        );

        setTimeout(() => {
          reject(new Error("timeout"));
        }, 60000);
      });

      // remove manager fee so that performance fee minting doesn't get in the way
      await poolManagerLogicProxy.connect(manager).setFeeNumerator("0", "0", "0");

      const totalSupply = await poolLogicProxy.totalSupply();

      const totalFundValue = await poolManagerLogicProxy.totalFundValue();
      const usdcBalance = await USDC.balanceOf(poolLogicProxy.address);
      const wethBalance = await WETH.balanceOf(poolLogicProxy.address);
      const usdcPrice = await assetHandler.getUSDPrice(assets.usdc);
      const wethPrice = await assetHandler.getUSDPrice(assets.weth);
      const sushiLPPrice = await assetHandler.getUSDPrice(sushi.pools.usdc_weth.address);
      const expectedFundValue = usdcBalance
        .mul(usdcPrice)
        .div(ethers.BigNumber.from("1000000"))
        .add(wethBalance.mul(wethPrice).div(units(1)))
        .add(availableLpToken.mul(sushiLPPrice).div(units(1)));

      checkAlmostSame(totalFundValue, expectedFundValue.toString());

      // Withdraw all
      const withdrawAmount = units(10);
      const investorFundBalance = await poolLogicProxy.balanceOf(logicOwner.address);

      const sushiBalanceBefore = await SUSHI.balanceOf(logicOwner.address);
      const wmaticBalanceBefore = await WMATIC.balanceOf(logicOwner.address);
      const lpBalanceBefore = await SushiLPUSDCWETH.balanceOf(logicOwner.address);

      ethers.provider.send("evm_increaseTime", [3600 * 24]); // add 1 day to avoid cooldown revert
      await poolLogicProxy.withdraw(withdrawAmount);

      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const eventWithdrawal: any = await withdrawalEvent;

      const valueWithdrawn = withdrawAmount.mul(totalFundValue).div(totalSupply);
      const expectedFundValueAfter = totalFundValue.sub(valueWithdrawn);

      expect(await SUSHI.balanceOf(logicOwner.address)).to.be.gt(sushiBalanceBefore);
      expect(await WMATIC.balanceOf(logicOwner.address)).to.be.gt(wmaticBalanceBefore);
      expect(await SushiLPUSDCWETH.balanceOf(logicOwner.address)).to.be.gt(lpBalanceBefore);

      expect(eventWithdrawal.fundAddress).to.equal(poolLogicProxy.address);
      expect(eventWithdrawal.investor).to.equal(logicOwner.address);
      checkAlmostSame(eventWithdrawal.valueWithdrawn, valueWithdrawn.toString());
      expect(eventWithdrawal.fundTokensWithdrawn).to.equal(withdrawAmount.toString());

      checkAlmostSame(eventWithdrawal.totalInvestorFundTokens, investorFundBalance.sub(withdrawAmount));
      checkAlmostSame(eventWithdrawal.fundValue, expectedFundValueAfter);
      checkAlmostSame(eventWithdrawal.totalSupply, totalSupply.sub(withdrawAmount));
    });
  });
});
