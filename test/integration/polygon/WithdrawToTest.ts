import { ethers } from "hardhat";
import { checkAlmostSame, units } from "../../testHelpers";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { IERC20, PoolFactory, PoolLogic, PoolManagerLogic } from "../../../types";
import { createFund } from "../utils/createFund";
import { getAccountToken } from "../utils/getAccountTokens";
import { deployContracts } from "../utils/deployContracts/deployContracts";

import { polygonChainData } from "../../../config/chainData/polygonData";
import { utils } from "../utils/utils";
const { assets, assetsBalanceOfSlot } = polygonChainData;

describe("WithdrawTo Test", function () {
  let USDC: IERC20;
  let logicOwner: SignerWithAddress, manager: SignerWithAddress, user: SignerWithAddress;
  let poolFactory: PoolFactory, poolLogicProxy: PoolLogic, poolManagerLogicProxy: PoolManagerLogic;

  let snapId: string;
  after(async () => {
    await utils.evmRestoreSnap(snapId);
  });

  before(async () => {
    snapId = await utils.evmTakeSnap();
    [logicOwner, manager, , user] = await ethers.getSigners();
    const deployments = await deployContracts("polygon");
    poolFactory = deployments.poolFactory;
    USDC = deployments.assets.USDC;

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

  it("able to withdrawTo", async function () {
    const withdrawAmount = units(20);

    const usdcBalanceBefore = await USDC.balanceOf(poolLogicProxy.address);
    const userBalanceBefore = await USDC.balanceOf(user.address);
    const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

    await ethers.provider.send("evm_increaseTime", [3600 * 24]); // add 1 day to avoid cooldown revert
    await poolLogicProxy.withdrawTo(user.address, withdrawAmount);

    const usdcBalanceAfter = await USDC.balanceOf(poolLogicProxy.address);
    const userBalanceAfter = await USDC.balanceOf(user.address);
    const totalFundValueAfter = await poolManagerLogicProxy.totalFundValue();

    checkAlmostSame(usdcBalanceBefore, units(20, 6).add(usdcBalanceAfter));
    checkAlmostSame(userBalanceAfter, units(20, 6).add(userBalanceBefore));
    checkAlmostSame(totalFundValueBefore, units(20).add(totalFundValueAfter));
  });
});
