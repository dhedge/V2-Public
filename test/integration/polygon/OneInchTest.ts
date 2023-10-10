import hre, { ethers } from "hardhat";
import { expect } from "chai";
import { checkAlmostSame, units } from "../../testHelpers";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { IERC20, IERC20__factory, MockContract, PoolFactory, PoolLogic, PoolManagerLogic } from "../../../types";
import { createFund } from "../utils/createFund";
import { polygonChainData } from "../../../config/chainData/polygonData";
const { oneinch, assets, assetsBalanceOfSlot, ZERO_ADDRESS } = polygonChainData;
import { getAccountToken } from "../utils/getAccountTokens";
import { IDeployments, deployContracts } from "../utils/deployContracts/deployContracts";
import { getOneInchSwapTransaction } from "../utils/oneInchHelpers";

import { utils } from "../utils/utils";

describe("OneInch Test", function () {
  let USDC: IERC20, USDT: IERC20;
  let logicOwner: SignerWithAddress, manager: SignerWithAddress, anon: SignerWithAddress;
  let poolFactory: PoolFactory, poolLogicProxy: PoolLogic, poolManagerLogicProxy: PoolManagerLogic;
  let evilPoolManager: MockContract;
  let deployments: IDeployments;
  const iERC20 = new ethers.utils.Interface(IERC20__factory.abi);

  let snapId: string;
  beforeEach(async () => {
    snapId = await utils.evmTakeSnap();
  });

  afterEach(async () => {
    await utils.evmRestoreSnap(snapId);
  });

  before(async () => {
    [logicOwner, manager, anon] = await ethers.getSigners();

    deployments = await deployContracts("polygon");
    poolFactory = deployments.poolFactory;
    USDC = deployments.assets.USDC;
    USDT = deployments.assets.USDT;

    const mockFactory = await ethers.getContractFactory("MockContract");
    evilPoolManager = await mockFactory.deploy();
    await evilPoolManager.deployed();

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

    approveABI = iERC20.encodeFunctionData("approve", [oneinch.v5Router, (200e6).toString()]);
    await poolLogicProxy.connect(manager).execTransaction(assets.usdc, approveABI);
  });

  it("should be able to swap tokens on oneInch - swap.", async () => {
    const srcAsset = assets.usdc;
    const dstAsset = assets.usdt;
    const srcAmount = units(1, 6);
    const fromAddress = poolLogicProxy.address;
    const toAddress = poolLogicProxy.address;

    let approveABI = iERC20.encodeFunctionData("approve", [assets.usdc, (200e6).toString()]);
    approveABI = iERC20.encodeFunctionData("approve", [oneinch.v5Router, (200e6).toString()]);
    await poolLogicProxy.connect(manager).execTransaction(assets.usdc, approveABI);

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
      chainId: 137,
    });

    await expect(poolLogicProxy.connect(manager).execTransaction(oneinch.v5Router, swapTx)).to.be.revertedWith(
      "unsupported destination asset",
    );

    swapTx = await getOneInchSwapTransaction({
      srcAsset,
      dstAsset,
      srcAmount,
      fromAddress,
      toAddress: ZERO_ADDRESS,
      chainId: 137,
    });

    await expect(poolLogicProxy.connect(manager).execTransaction(oneinch.v5Router, swapTx)).to.be.revertedWith(
      "recipient is not pool",
    );

    swapTx = await getOneInchSwapTransaction({
      srcAsset,
      dstAsset,
      srcAmount,
      fromAddress,
      toAddress,
      chainId: 137,
    });

    const usdtBalanceBefore = ethers.BigNumber.from(await USDT.balanceOf(poolLogicProxy.address));
    const usdcBalanceBefore = ethers.BigNumber.from(await USDC.balanceOf(poolLogicProxy.address));

    await poolLogicProxy.connect(manager).execTransaction(oneinch.v5Router, swapTx);

    const usdtBalanceAfter = await USDT.balanceOf(poolLogicProxy.address);
    const usdcBalanceAfter = await USDC.balanceOf(poolLogicProxy.address);
    checkAlmostSame(usdcBalanceAfter, usdcBalanceBefore.sub(srcAmount));
    checkAlmostSame(usdtBalanceAfter, usdtBalanceBefore.add(srcAmount));
  });

  it("should revert if caller is not the manager but affects the pool of some manager", async () => {
    const srcAsset = assets.usdc;
    const dstAsset = assets.usdt;
    const srcAmount = units(1, 6);
    const fromAddress = poolLogicProxy.address;
    const toAddress = poolLogicProxy.address;

    const swapTx = await getOneInchSwapTransaction({
      srcAsset,
      dstAsset,
      srcAmount,
      fromAddress,
      toAddress,
      chainId: 137,
    });

    const poolManagerABI = await hre.artifacts.readArtifact(
      "contracts/interfaces/IPoolManagerLogic.sol:IPoolManagerLogic",
    );
    const hasSupportedAssetABI = await hre.artifacts.readArtifact(
      "contracts/interfaces/IHasSupportedAsset.sol:IHasSupportedAsset",
    );
    const iHasSupportedAsset = new ethers.utils.Interface(hasSupportedAssetABI.abi);
    const iPoolManager = new ethers.utils.Interface(poolManagerABI.abi);

    await evilPoolManager.givenCalldataReturnAddress(
      iPoolManager.encodeFunctionData("poolLogic", []),
      poolLogicProxy.address,
    );

    await evilPoolManager.givenCalldataReturnBool(
      iHasSupportedAsset.encodeFunctionData("isSupportedAsset", [dstAsset]),
      true,
    );

    await expect(
      deployments.oneInchV5Guard?.connect(anon).txGuard(evilPoolManager.address, oneinch.v5Router, swapTx),
    ).to.be.revertedWith("Caller not authorised");

    await expect(
      deployments.oneInchV5Guard?.connect(anon).txGuard(poolManagerLogicProxy.address, oneinch.v5Router, swapTx),
    ).to.be.revertedWith("Caller not authorised");

    expect(
      (await deployments.slippageAccumulator.managerData(poolManagerLogicProxy.address)).accumulatedSlippage,
    ).to.equal(ethers.constants.Zero, "Slippage impact detected after");
  });
});
