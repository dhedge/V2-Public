import { ethers } from "hardhat";
import { solidity } from "ethereum-waffle";
import { expect, use } from "chai";
import { checkAlmostSame, units } from "../../TestHelpers";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { IERC20, IERC20__factory, PoolFactory, PoolLogic, PoolManagerLogic } from "../../../types";
import { createFund } from "../utils/createFund";
import { assets, assetsBalanceOfSlot, oneinch, ZERO_ADDRESS } from "../../../config/chainData/polygon-data";
import { getAccountToken } from "../utils/getAccountTokens";
import { deployContracts } from "../utils/deployContracts";
const axios = require("axios");

use(solidity);

describe("OneInch V3 Test", function () {
  let WMATIC: IERC20, USDC: IERC20, USDT: IERC20;
  let logicOwner: SignerWithAddress, manager: SignerWithAddress, dao: SignerWithAddress;
  let poolFactory: PoolFactory, poolLogicProxy: PoolLogic, poolManagerLogicProxy: PoolManagerLogic;
  const iERC20 = new ethers.utils.Interface(IERC20__factory.abi);

  before(async function () {
    [logicOwner, manager, dao] = await ethers.getSigners();

    const deployments = await deployContracts("polygon");
    poolFactory = deployments.poolFactory;
    WMATIC = deployments.assets.WMATIC!;
    USDC = deployments.assets.USDC;
    USDT = deployments.assets.USDT;

    await getAccountToken(units(10000, 6), logicOwner.address, assets.usdc, assetsBalanceOfSlot.usdc);

    const funds = await createFund(poolFactory, logicOwner, manager, [
      { asset: assets.usdc, isDeposit: true },
      { asset: assets.usdt, isDeposit: true },
    ]);
    poolLogicProxy = funds.poolLogicProxy;
    poolManagerLogicProxy = funds.poolManagerLogicProxy;

    // Deposit 200 USDC
    await USDC.approve(poolLogicProxy.address, units(200, 6));
    await poolLogicProxy.deposit(assets.usdc, units(200, 6));
  });

  it("Should be able to approve", async () => {
    let approveABI = iERC20.encodeFunctionData("approve", [assets.usdc, (200e6).toString()]);
    await expect(poolLogicProxy.connect(manager).execTransaction(assets.weth, approveABI)).to.be.revertedWith(
      "asset not enabled in pool",
    );

    await expect(poolLogicProxy.connect(manager).execTransaction(assets.usdc, approveABI)).to.be.revertedWith(
      "unsupported spender approval",
    );

    approveABI = iERC20.encodeFunctionData("approve", [oneinch.v3Router, (200e6).toString()]);
    await poolLogicProxy.connect(manager).execTransaction(assets.usdc, approveABI);
  });

  it("should be able to swap tokens on oneInch - swap.", async () => {
    const srcAsset = assets.usdc;
    const dstAsset = assets.usdt;
    const srcAmount = units(1, 6);
    const fromAddress = poolLogicProxy.address;
    const toAddress = poolLogicProxy.address;
    const referrerAddress = "";

    /**
     * Example Swap Transaction USDT -> USDC
     * 0x7c02520000000000000000000000000027239549dd40e1d60f5b80b0c4196923745b1fd200000000000000000000000000000000000000000000000000000000000000600000000000000000000000000000000000000000000000000000000000000180000000000000000000000000dac17f958d2ee523a2206206994597c13d831ec7000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb4800000000000000000000000027239549dd40e1d60f5b80b0c4196923745b1fd20000000000000000000000004f6d9fd7e4ce9a64b1d3e62c6fa9cf186b5e8c3d00000000000000000000000000000000000000000000000000000002540be400000000000000000000000000000000000000000000000000000000024e07705c00000000000000000000000000000000000000000000000000000000000000040000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002a0000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000040000000000000000000000000000000000000000000000000000000000000016080000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000800000000000000000000000000000000000000000000000000000000000000064eb5625d9000000000000000000000000dac17f958d2ee523a2206206994597c13d831ec700000000000000000000000040bbde0ec6f177c4a67360d0f0969cfc464b0bb400000000000000000000000000000000000000000000000000000002540be4000000000000000000000000000000000000000000000000000000000080000000000000000000000040bbde0ec6f177c4a67360d0f0969cfc464b0bb40000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000800000000000000000000000000000000000000000000000000000000000000044404a1f8a00000000000000000000000000000000000000000000000000000002540be4000000000000000000000000004f6d9fd7e4ce9a64b1d3e62c6fa9cf186b5e8c3d00000000000000000000000000000000000000000000000000000000
     * Example Swap Transaction USDC -> USDT
     * 0x7c02520000000000000000000000000027239549dd40e1d60f5b80b0c4196923745b1fd200000000000000000000000000000000000000000000000000000000000000600000000000000000000000000000000000000000000000000000000000000180000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb48000000000000000000000000dac17f958d2ee523a2206206994597c13d831ec700000000000000000000000027239549dd40e1d60f5b80b0c4196923745b1fd20000000000000000000000004f6d9fd7e4ce9a64b1d3e62c6fa9cf186b5e8c3d000000000000000000000000000000000000000000000000000000046c7cfe000000000000000000000000000000000000000000000000000000000460e6d94800000000000000000000000000000000000000000000000000000000000000040000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002a0000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000040000000000000000000000000000000000000000000000000000000000000016080000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000800000000000000000000000000000000000000000000000000000000000000064eb5625d9000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb4800000000000000000000000040bbde0ec6f177c4a67360d0f0969cfc464b0bb4000000000000000000000000000000000000000000000000000000046c7cfe000000000000000000000000000000000000000000000000000000000080000000000000000000000040bbde0ec6f177c4a67360d0f0969cfc464b0bb400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000000000000000000000448999541a000000000000000000000000000000000000000000000000000000046c7cfe000000000000000000000000004f6d9fd7e4ce9a64b1d3e62c6fa9cf186b5e8c3d00000000000000000000000000000000000000000000000000000000
     */
    let swapTx = await getOneInchSwapTransaction({
      srcAsset,
      dstAsset: assets.dai,
      srcAmount,
      fromAddress,
      toAddress,
      referrerAddress,
    });

    await expect(poolLogicProxy.connect(manager).execTransaction(oneinch.v3Router, swapTx)).to.be.revertedWith(
      "unsupported destination asset",
    );

    swapTx = await getOneInchSwapTransaction({
      srcAsset,
      dstAsset,
      srcAmount,
      fromAddress,
      toAddress: ZERO_ADDRESS,
      referrerAddress,
    });

    await expect(poolLogicProxy.connect(manager).execTransaction(oneinch.v3Router, swapTx)).to.be.revertedWith(
      "recipient is not pool",
    );

    swapTx = await getOneInchSwapTransaction({
      srcAsset,
      dstAsset,
      srcAmount,
      fromAddress,
      toAddress,
      referrerAddress,
    });

    const usdtBalanceBefore = ethers.BigNumber.from(await USDT.balanceOf(poolLogicProxy.address));
    const usdcBalanceBefore = ethers.BigNumber.from(await USDC.balanceOf(poolLogicProxy.address));

    await poolLogicProxy.connect(manager).execTransaction(oneinch.v3Router, swapTx);

    const usdtBalanceAfter = await USDT.balanceOf(poolLogicProxy.address);
    const usdcBalanceAfter = await USDC.balanceOf(poolLogicProxy.address);
    checkAlmostSame(usdcBalanceAfter, usdcBalanceBefore.sub(srcAmount));
    checkAlmostSame(usdtBalanceAfter, usdtBalanceBefore.add(srcAmount));
  });
});

const getOneInchSwapTransaction = async (params: {
  srcAsset: any;
  dstAsset: any;
  srcAmount: any;
  fromAddress: any;
  toAddress: any;
  referrerAddress: any;
}) => {
  const { srcAsset, dstAsset, srcAmount, fromAddress, toAddress, referrerAddress } = params;
  const apiUrl = `https://api.1inch.exchange/v4.0/137/swap?fromTokenAddress=${srcAsset}&toTokenAddress=${dstAsset}&amount=${srcAmount.toString()}&fromAddress=${fromAddress}&destReceiver=${toAddress}&referrerAddress=${referrerAddress}&slippage=1&disableEstimate=true`;
  const response = await axios.get(apiUrl);
  const calldata = response.data.tx.data;

  return calldata;
};
