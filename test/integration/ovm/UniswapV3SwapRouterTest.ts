import { ethers, artifacts } from "hardhat";
import { expect } from "chai";
import { ZERO_ADDRESS, uniswapV3, assets } from "../../../config/chainData/ovm-data";
import {
  AssetHandler,
  IERC20,
  IERC20__factory,
  IMulticall__factory,
  IV3SwapRouter__factory,
  PoolFactory,
  PoolLogic,
  PoolManagerLogic,
} from "../../../types";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { getMinAmountOut } from "../utils/getMinAmountOut";
import { deployOVMContracts } from "../utils/deployContracts/deployOVMContracts";
import { createFund } from "../utils/createFund";
import { getAccountToken } from "../utils/getAccountTokens";
import { units } from "../../TestHelpers";
import { assetsBalanceOfSlot } from "../../../config/chainData/ovm-data";
import { Deployments } from "../utils/deployContracts";

describe("Uniswap V3 Swap Router Test", function () {
  let deployments: Deployments;
  let WETH: IERC20, USDT: IERC20, USDC: IERC20;
  let logicOwner: SignerWithAddress, manager: SignerWithAddress, dao: SignerWithAddress, user: SignerWithAddress;
  let assetHandler: AssetHandler;
  let poolFactory: PoolFactory, poolLogicProxy: PoolLogic, poolManagerLogicProxy: PoolManagerLogic;
  const iERC20 = new ethers.utils.Interface(IERC20__factory.abi);
  const iV3SwapRouter = new ethers.utils.Interface(IV3SwapRouter__factory.abi);
  const iMulticall = new ethers.utils.Interface(IMulticall__factory.abi);

  before(async function () {
    [logicOwner, manager, dao, user] = await ethers.getSigners();

    deployments = await deployOVMContracts();
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

  it("USDC -> WETH: exactInputSingle", async () => {
    const sourceAmount = ethers.BigNumber.from((5e6).toString());
    const minAmountOut = await getMinAmountOut(
      deployments,
      ethers.BigNumber.from(sourceAmount),
      USDC.address,
      WETH.address,
    );
    const exactInputSingleParams = {
      tokenIn: assets.usdc,
      tokenOut: assets.weth,
      fee: 10000,
      recipient: poolLogicProxy.address,
      amountIn: sourceAmount,
      amountOutMinimum: minAmountOut,
      sqrtPriceLimitX96: 0,
    };
    let badExactInputSingleParams = exactInputSingleParams;

    // fail to swap direct asset to asset because it is interaction is with 0x0 address
    let swapABI = iV3SwapRouter.encodeFunctionData("exactInputSingle", [exactInputSingleParams]);
    await expect(
      poolLogicProxy.connect(manager).execTransaction("0x0000000000000000000000000000000000000000", swapABI),
    ).to.be.revertedWith("non-zero address is required");

    // fail to swap direct asset to asset because unsupported destination asset
    badExactInputSingleParams.tokenOut = assets.usdt;
    swapABI = iV3SwapRouter.encodeFunctionData("exactInputSingle", [badExactInputSingleParams]);
    await expect(poolLogicProxy.connect(manager).execTransaction(uniswapV3.router, swapABI)).to.be.revertedWith(
      "unsupported destination asset",
    );
    badExactInputSingleParams.tokenOut = assets.weth;

    // fail to swap direct asset to asset because recipient is not the pool address
    badExactInputSingleParams.recipient = user.address;
    swapABI = iV3SwapRouter.encodeFunctionData("exactInputSingle", [badExactInputSingleParams]);
    await expect(poolLogicProxy.connect(manager).execTransaction(uniswapV3.router, swapABI)).to.be.revertedWith(
      "recipient is not pool",
    );
    exactInputSingleParams.recipient = poolLogicProxy.address;

    // succeed swapping direct asset to asset
    swapABI = iV3SwapRouter.encodeFunctionData("exactInputSingle", [exactInputSingleParams]);
    await poolLogicProxy.connect(manager).execTransaction(uniswapV3.router, swapABI);
  });

  it("WETH -> USDT: exactInput", async () => {
    await poolManagerLogicProxy.connect(manager).changeAssets(
      [
        {
          asset: assets.usdt,
          isDeposit: false,
        },
      ],
      [],
    );

    const sourceAmount = (1e18).toString();
    const minAmountOut = await getMinAmountOut(
      deployments,
      ethers.BigNumber.from(sourceAmount),
      WETH.address,
      USDT.address,
    );
    const IV3SwapRouter = await artifacts.readArtifact("IV3SwapRouter");
    const iV3SwapRouter = new ethers.utils.Interface(IV3SwapRouter.abi);
    // https://etherscan.io/tx/0xf74db2cc2a321de029800754ed3c8c7b85a9e1233e3bd2001218d0f407fd3a93
    // data on etherscan: 0xc04b8d59000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000a000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000060f1c58700000000000000000000000000000000000000000000000000000001126dc7d6000000000000000000000000000000000000000000000000210a5097b6c2a7010000000000000000000000000000000000000000000000000000000000000042
    // dac17f958d2ee523a2206206994597c13d831ec7 0001f4 a0b86991c6218b36c1d19d4a2e9eb0ce3606eb48 0001f4 c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2000000000000000000000000000000000000000000000000000000000000

    // data we have:      0xc04b8d59000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000a0000000000000000000000000893bacb707c0c0d9a46a3eaea2c3b44df449137b0000000000000000000000000000000000000000000000000000000066e7a8180000000000000000000000000000000000000000000000008ac7230489e8000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000042
    // a0b86991c6218b36c1d19d4a2e9eb0ce3606eb48 000bb8 c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2 000bb8 dac17f958d2ee523a2206206994597c13d831ec7000000000000000000000000000000000000000000000000000000000000

    // path on etherscan: 0x dac17f958d2ee523a2206206994597c13d831ec7 0001f4 a0b86991c6218b36c1d19d4a2e9eb0ce3606eb48 0001f4 c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2
    // path we have:      0x C02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2 0001f4 A0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48 0001f4 dAC17F958D2ee523a2206206994597C13D831ec7
    const path =
      "0x" +
      assets.weth.substring(2) + // source asset
      "0001f4" + // fee
      assets.usdc.substring(2) + // path asset
      "0001f4" + // fee
      assets.usdt.substring(2); // destination asset
    const exactInputParams = {
      path: path,
      recipient: poolLogicProxy.address,
      amountIn: sourceAmount,
      amountOutMinimum: minAmountOut,
    };
    let badExactInputParams = exactInputParams;
    let badPath = path;

    // fail to swap direct asset to asset because it is interaction is with 0x0 address
    let swapABI = iV3SwapRouter.encodeFunctionData("exactInput", [exactInputParams]);
    await expect(poolLogicProxy.connect(manager).execTransaction(ZERO_ADDRESS, swapABI)).to.be.revertedWith(
      "non-zero address is required",
    );

    // // TODO: add invalid path asset check if enabled in the Uniswap V3 swap guard
    // // fail to swap direct asset to asset because invalid path asset, unsupported by dhedge protocol
    // badExactInputParams.path =
    //   '0x' +
    //   assets.susd.substring(2) +
    //   '000bb8' +
    //   badtoken.substring(2) + // invalid asset
    //   '000bb8' +
    //   assets.seth.substring(2);
    // swapABI = iV3SwapRouter.encodeFunctionData('exactInput', [badExactInputParams]);
    // await expect(poolLogicProxy.connect(manager).execTransaction(uniswapV3.router.address, swapABI)).to.be.revertedWith(
    //   'invalid path asset',
    // );

    // fail to swap direct asset to asset because unsupported destination asset
    badExactInputParams.path =
      "0x" + assets.weth.substring(2) + "000bb8" + assets.usdc.substring(2) + "000bb8" + assets.sbtc.substring(2); // unsupported asset
    swapABI = iV3SwapRouter.encodeFunctionData("exactInput", [badExactInputParams]);
    await expect(poolLogicProxy.connect(manager).execTransaction(uniswapV3.router, swapABI)).to.be.revertedWith(
      "unsupported destination asset",
    );
    badExactInputParams.path = path;

    // fail to swap direct asset to asset because recipient is not the pool address
    badExactInputParams.recipient = user.address;
    swapABI = iV3SwapRouter.encodeFunctionData("exactInput", [exactInputParams]);
    await expect(poolLogicProxy.connect(manager).execTransaction(uniswapV3.router, swapABI)).to.be.revertedWith(
      "recipient is not pool",
    );

    exactInputParams.recipient = poolLogicProxy.address;
    // succeed swapping direct asset to asset
    swapABI = iV3SwapRouter.encodeFunctionData("exactInput", [exactInputParams]);
    await poolLogicProxy.connect(manager).execTransaction(uniswapV3.router, swapABI);
  });

  it("USDC -> WETH: multicall(exactInputSingle, exactInputSingle)", async () => {
    const sourceAmount = ethers.BigNumber.from((5e6).toString());
    const minAmountOut = await getMinAmountOut(
      deployments,
      ethers.BigNumber.from(sourceAmount),
      USDC.address,
      WETH.address,
    );
    const exactInputSingleParams = {
      tokenIn: assets.usdc,
      tokenOut: assets.weth,
      fee: 10000,
      recipient: poolLogicProxy.address,
      amountIn: sourceAmount,
      amountOutMinimum: minAmountOut,
      sqrtPriceLimitX96: 0,
    };
    const swapABI = iV3SwapRouter.encodeFunctionData("exactInputSingle", [exactInputSingleParams]);
    const multicallABI = iMulticall.encodeFunctionData("multicall", [[swapABI, swapABI]]);

    await poolLogicProxy.connect(manager).execTransaction(uniswapV3.router, multicallABI);
  });
});
