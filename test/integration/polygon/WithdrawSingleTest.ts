import { ethers } from "hardhat";
import { solidity } from "ethereum-waffle";
import { expect, use } from "chai";
import { checkAlmostSame, getAmountOut, units } from "../../TestHelpers";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import {
  IBalancerV2Vault__factory,
  IERC20,
  IERC20__factory,
  IUniswapV2Router__factory,
  PoolFactory,
  PoolLogic,
  PoolManagerLogic,
} from "../../../types";
import { deployPolygonContracts } from "../utils/deployContracts/deployPolygonContracts";
import { createFund } from "../utils/createFund";
import { assets, assetsBalanceOfSlot, quickswap } from "../polygon-data";
import { getAccountToken } from "../utils/getAccountTokens";

use(solidity);

describe("WithdrawSingle Test", function () {
  let WETH: IERC20, USDC: IERC20, QuickLPUSDCWETH: IERC20, QUICK: IERC20;
  let logicOwner: SignerWithAddress, manager: SignerWithAddress, dao: SignerWithAddress, user: SignerWithAddress;
  let poolFactory: PoolFactory, poolLogicProxy: PoolLogic, poolManagerLogicProxy: PoolManagerLogic;
  const iERC20 = new ethers.utils.Interface(IERC20__factory.abi);
  const iQuickswapRouter = new ethers.utils.Interface(IUniswapV2Router__factory.abi);
  const iBalancerV2Vault = new ethers.utils.Interface(IBalancerV2Vault__factory.abi);

  before(async function () {
    [logicOwner, manager, dao, user] = await ethers.getSigners();
    const deployments = await deployPolygonContracts();
    poolFactory = deployments.poolFactory;
    USDC = deployments.assets.USDC;
    WETH = deployments.assets.WETH;
    QUICK = deployments.assets.QUICK;
    QuickLPUSDCWETH = deployments.assets.QuickLPUSDCWETH;

    await getAccountToken(units(10000, 6), logicOwner.address, assets.usdc, assetsBalanceOfSlot.usdc);
    await getAccountToken(units(10000), logicOwner.address, assets.weth, assetsBalanceOfSlot.weth);

    const funds = await createFund(poolFactory, logicOwner, manager, [
      { asset: assets.usdc, isDeposit: true },
      { asset: assets.usdt, isDeposit: true },
    ]);
    poolLogicProxy = funds.poolLogicProxy;
    poolManagerLogicProxy = funds.poolManagerLogicProxy;
    // Deposit 1000 USDC
    await USDC.approve(poolLogicProxy.address, units(1000, 6));
    await poolLogicProxy.deposit(assets.usdc, units(1000, 6));
  });

  it("Approve 750 USDC", async () => {
    const approveABI = iERC20.encodeFunctionData("approve", [quickswap.router, units(750, 6).toString()]);
    await poolLogicProxy.connect(manager).execTransaction(assets.usdc, approveABI);
  });

  it("Swap 750 USDC to WETH", async () => {
    await poolManagerLogicProxy.connect(manager).changeAssets([{ asset: assets.weth, isDeposit: false }], []);

    const sourceAmount = units(750, 6);
    const swapABI = iQuickswapRouter.encodeFunctionData("swapExactTokensForTokens", [
      sourceAmount,
      await getAmountOut(quickswap.router, sourceAmount, [assets.usdc, assets.weth]),
      [assets.usdc, assets.weth],
      poolLogicProxy.address,
      Math.floor(Date.now() / 1000 + 100000000),
    ]);
    await poolLogicProxy.connect(manager).execTransaction(quickswap.router, swapABI);

    checkAlmostSame(await USDC.balanceOf(poolLogicProxy.address), units(250, 6));
  });

  it("not able to withdrawSingle 300 USDC", async function () {
    ethers.provider.send("evm_increaseTime", [3600 * 24]); // add 1 day to avoid cooldown revert
    await expect(poolLogicProxy.withdrawSingle(units(10000), assets.usdc)).to.be.revertedWith("insufficient balance");

    const withdrawAmount = units(300);
    await expect(poolLogicProxy.withdrawSingle(withdrawAmount, assets.quick)).to.be.revertedWith(
      "invalid deposit asset",
    );
    await expect(poolLogicProxy.withdrawSingle(withdrawAmount, assets.usdc)).to.be.revertedWith(
      "insufficient asset amount",
    );

    const withdrawMaxAmount = await poolLogicProxy.getWithdrawSingleMax(assets.usdc);
    checkAlmostSame(withdrawMaxAmount, units(250).mul(101).div(100));
  });

  // Disabled early withdraw for now
  // it("able to withdrawSingle 200 USDC (early withdraw)", async function () {
  //   const withdrawAmount = units(200);

  //   const usdcBalanceBefore = await USDC.balanceOf(poolLogicProxy.address);
  //   const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();
  //   const withdrawMaxAmountBefore = await poolLogicProxy.getWithdrawSingleMax(assets.usdc);

  //   await poolLogicProxy.withdrawSingle(withdrawAmount, assets.usdc);

  //   const usdcBalanceAfter = await USDC.balanceOf(poolLogicProxy.address);
  //   const totalFundValueAfter = await poolManagerLogicProxy.totalFundValue();

  //   // check with remove 0.5% exit fee
  //   checkAlmostSame(usdcBalanceBefore, units(199, 6).add(usdcBalanceAfter));
  //   checkAlmostSame(totalFundValueBefore, units(199).add(totalFundValueAfter));

  //   checkAlmostSame(
  //     withdrawMaxAmountBefore,
  //     withdrawAmount.add(await poolLogicProxy.getWithdrawSingleMax(assets.usdc)),
  //   );
  // });

  it("able to withdrawSingle 20 USDC", async function () {
    const withdrawAmount = units(20);

    const usdcBalanceBefore = await USDC.balanceOf(poolLogicProxy.address);
    const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();
    const withdrawMaxAmountBefore = await poolLogicProxy.getWithdrawSingleMax(assets.usdc);

    ethers.provider.send("evm_increaseTime", [3600 * 24]); // add 1 day to avoid cooldown revert
    await poolLogicProxy.withdrawSingle(withdrawAmount, assets.usdc);

    const usdcBalanceAfter = await USDC.balanceOf(poolLogicProxy.address);
    const totalFundValueAfter = await poolManagerLogicProxy.totalFundValue();

    checkAlmostSame(usdcBalanceBefore, units(20, 6).add(usdcBalanceAfter));
    checkAlmostSame(totalFundValueBefore, units(20).add(totalFundValueAfter));

    checkAlmostSame(
      withdrawMaxAmountBefore,
      withdrawAmount.add(await poolLogicProxy.getWithdrawSingleMax(assets.usdc)),
    );
  });
});
