import { ethers } from "hardhat";
import { expect } from "chai";
import { uniswapV3, assets } from "../../../config/chainData/ovm-data";
import {
  IERC20,
  IERC20__factory,
  IMulticallExtended__factory,
  IV3SwapRouter__factory,
  PoolFactory,
  PoolLogic,
  PoolManagerLogic,
} from "../../../types";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { getMinAmountOut } from "../utils/getMinAmountOut";
import { createFund } from "../utils/createFund";
import { getAccountToken } from "../utils/getAccountTokens";
import { checkAlmostSame, units } from "../../TestHelpers";
import { assetsBalanceOfSlot } from "../../../config/chainData/ovm-data";
import { deployContracts, IDeployments } from "../utils/deployContracts";

describe("Uniswap V3 Swap Router Test", function () {
  let deployments: IDeployments;
  let WETH: IERC20, USDT: IERC20, USDC: IERC20;
  let logicOwner: SignerWithAddress, manager: SignerWithAddress, dao: SignerWithAddress, user: SignerWithAddress;
  let poolFactory: PoolFactory, poolLogicProxy: PoolLogic, poolManagerLogicProxy: PoolManagerLogic;
  const iERC20 = new ethers.utils.Interface(IERC20__factory.abi);
  const iV3SwapRouter = new ethers.utils.Interface(IV3SwapRouter__factory.abi);
  const iMulticall = new ethers.utils.Interface(IMulticallExtended__factory.abi);

  before(async function () {
    [logicOwner, manager, dao, user] = await ethers.getSigners();

    deployments = await deployContracts("ovm");
    poolFactory = deployments.poolFactory;
    WETH = deployments.assets.WETH;
    USDC = deployments.assets.USDC;
    USDT = deployments.assets.USDC;
  });

  beforeEach(async function () {
    const funds = await createFund(poolFactory, logicOwner, manager, [
      { asset: assets.usdc, isDeposit: true },
      { asset: assets.weth, isDeposit: true },
    ]);
    poolLogicProxy = funds.poolLogicProxy;
    poolManagerLogicProxy = funds.poolManagerLogicProxy;

    await getAccountToken(units(5), logicOwner.address, assets.weth, assetsBalanceOfSlot.weth);
    await getAccountToken(units(10000, 6), logicOwner.address, assets.usdc, assetsBalanceOfSlot.usdc);

    await USDC.approve(poolLogicProxy.address, units(10000, 6));
    await poolLogicProxy.deposit(assets.usdc, units(10000, 6));

    await WETH.approve(poolLogicProxy.address, units(5));
    await poolLogicProxy.deposit(assets.weth, units(5));

    // Approve to swap 100 USDC
    let approveABI = iERC20.encodeFunctionData("approve", [uniswapV3.router, units(100, 6)]);
    await poolLogicProxy.connect(manager).execTransaction(assets.usdc, approveABI);

    // Approve to swap 1 WETH
    approveABI = iERC20.encodeFunctionData("approve", [uniswapV3.router, units(1)]);
    await poolLogicProxy.connect(manager).execTransaction(assets.weth, approveABI);

    await poolFactory.setExitCooldown(0);
  });

  it("Should be able to swap USDC to WETH", async () => {
    const usdcSwapAmount = units(100, 6); // 100 USDC

    const minAmountOut = await getMinAmountOut(deployments, usdcSwapAmount, USDC.address, WETH.address);

    let exactInputSingleCalldata = iV3SwapRouter.encodeFunctionData("exactInputSingle", [
      [
        USDC.address, // from
        WETH.address, // to
        500, // 0.05% fee
        poolLogicProxy.address,
        usdcSwapAmount,
        minAmountOut,
        0,
      ],
    ]);

    const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();
    await poolLogicProxy.connect(manager).execTransaction(uniswapV3.router, exactInputSingleCalldata);
    const totalFundValueAfter = await poolManagerLogicProxy.totalFundValue();

    checkAlmostSame(totalFundValueAfter, totalFundValueBefore);
  });

  it("Should be able to swap WETH to USDC", async () => {
    const ethSwapAmount = units(1, 18); // 1 ETH

    const minAmountOut = await getMinAmountOut(deployments, ethSwapAmount, WETH.address, USDC.address);

    const exactInputSingleCalldata = iV3SwapRouter.encodeFunctionData("exactInputSingle", [
      [
        WETH.address, // from
        USDC.address, // to
        500, // 0.05% fee
        poolLogicProxy.address,
        ethSwapAmount,
        minAmountOut,
        0,
      ],
    ]);

    const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();
    await poolLogicProxy.connect(manager).execTransaction(uniswapV3.router, exactInputSingleCalldata);
    const totalFundValueAfter = await poolManagerLogicProxy.totalFundValue();

    checkAlmostSame(totalFundValueAfter, totalFundValueBefore);
  });

  it("Should be able to swap with Multicall", async () => {
    const ethSwapAmount = units(1, 18); // 1 ETH

    const minAmountOut = await getMinAmountOut(deployments, ethSwapAmount, WETH.address, USDC.address);

    const exactInputSingleCalldata = iV3SwapRouter.encodeFunctionData("exactInputSingle", [
      [
        WETH.address, // from
        USDC.address, // to
        500, // 0.05% fee
        poolLogicProxy.address,
        ethSwapAmount,
        minAmountOut,
        0,
      ],
    ]);

    // First check that the multicall is executing by executing an out of date transaction deadline
    const deadlineOld = Math.floor(Date.now() / 1000 - 100000000);
    let multicallCalldata = iMulticall.encodeFunctionData("multicall(uint256,bytes[])", [
      deadlineOld,
      [exactInputSingleCalldata],
    ]);
    await expect(
      poolLogicProxy.connect(manager).execTransaction(uniswapV3.router, multicallCalldata),
    ).to.be.revertedWith("Transaction too old");

    const deadline = Math.floor(Date.now() / 1000 + 100000000);
    multicallCalldata = iMulticall.encodeFunctionData("multicall(uint256,bytes[])", [
      deadline,
      [exactInputSingleCalldata],
    ]);

    const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();
    await poolLogicProxy.connect(manager).execTransaction(uniswapV3.router, multicallCalldata);
    const totalFundValueAfter = await poolManagerLogicProxy.totalFundValue();

    checkAlmostSame(totalFundValueAfter, totalFundValueBefore);
  });
});
