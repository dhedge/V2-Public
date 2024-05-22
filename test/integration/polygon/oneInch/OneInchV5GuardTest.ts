import hre, { ethers } from "hardhat";
import { expect } from "chai";
import { checkAlmostSame, units } from "../../../testHelpers";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { IERC20, IERC20__factory, MockContract, PoolFactory, PoolLogic, PoolManagerLogic } from "../../../../types";
import { createFund } from "../../utils/createFund";
import { polygonChainData } from "../../../../config/chainData/polygonData";
import { getAccountToken } from "../../utils/getAccountTokens";
import { IDeployments, deployContracts } from "../../utils/deployContracts/deployContracts";
import { getOneInchSwapTransaction } from "../../utils/oneInchHelpers";
import { utils } from "../../utils/utils";

const { oneinch, assets, assetsBalanceOfSlot, ZERO_ADDRESS } = polygonChainData;

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
    const src = assets.usdc;
    const dst = assets.usdt;
    const amount = units(1, 6);
    const from = poolLogicProxy.address;
    const receiver = poolLogicProxy.address;

    let approveABI = iERC20.encodeFunctionData("approve", [assets.usdc, (200e6).toString()]);
    approveABI = iERC20.encodeFunctionData("approve", [oneinch.v5Router, (200e6).toString()]);
    await poolLogicProxy.connect(manager).execTransaction(assets.usdc, approveABI);

    let swapTx = await getOneInchSwapTransaction({
      src,
      dst: assets.dai,
      amount,
      from,
      receiver,
      chainId: 137,
    });

    await expect(poolLogicProxy.connect(manager).execTransaction(oneinch.v5Router, swapTx)).to.be.revertedWith(
      "unsupported destination asset",
    );

    await utils.delay();

    swapTx = await getOneInchSwapTransaction({
      src,
      dst,
      amount,
      from,
      receiver: ZERO_ADDRESS,
      chainId: 137,
    });

    await expect(poolLogicProxy.connect(manager).execTransaction(oneinch.v5Router, swapTx)).to.be.revertedWith(
      "recipient is not pool",
    );

    await utils.delay();

    swapTx = await getOneInchSwapTransaction({
      src,
      dst,
      amount,
      from,
      receiver,
      chainId: 137,
    });

    const usdtBalanceBefore = ethers.BigNumber.from(await USDT.balanceOf(poolLogicProxy.address));
    const usdcBalanceBefore = ethers.BigNumber.from(await USDC.balanceOf(poolLogicProxy.address));

    await poolLogicProxy.connect(manager).execTransaction(oneinch.v5Router, swapTx);

    const usdtBalanceAfter = await USDT.balanceOf(poolLogicProxy.address);
    const usdcBalanceAfter = await USDC.balanceOf(poolLogicProxy.address);
    checkAlmostSame(usdcBalanceAfter, usdcBalanceBefore.sub(amount));
    checkAlmostSame(usdtBalanceAfter, usdtBalanceBefore.add(amount));
  });

  it("should revert if caller is not the manager but affects the pool of some manager", async () => {
    const src = assets.usdc;
    const dst = assets.usdt;
    const amount = units(1, 6);
    const from = poolLogicProxy.address;
    const receiver = poolLogicProxy.address;

    await utils.delay();

    const swapTx = await getOneInchSwapTransaction({
      src,
      dst,
      amount,
      from,
      receiver,
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
      iHasSupportedAsset.encodeFunctionData("isSupportedAsset", [dst]),
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
