import { ethers, upgrades, artifacts } from "hardhat";
import { expect } from "chai";
import { ZERO_ADDRESS, uniswapV3, assets, price_feeds } from "./ovm-data";
import {
  AssetHandler,
  IERC20,
  IV3SwapRouter,
  IWETH,
  PoolFactory,
  PoolFactory__factory,
  PoolLogic,
  PoolLogic__factory,
  PoolManagerLogic,
  PoolManagerLogic__factory,
} from "../../../types";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { getMinAmountOut } from "../utils/getMinAmountOut";

describe("Uniswap V3 Swap Router Test", function () {
  let WETH: IWETH, USDT: IERC20, USDC: IERC20, UniswapRouter: IV3SwapRouter;
  let logicOwner: SignerWithAddress, manager: SignerWithAddress, dao: SignerWithAddress, user: SignerWithAddress;
  let PoolFactory: PoolFactory__factory,
    PoolLogic: PoolLogic__factory,
    PoolManagerLogic: PoolManagerLogic__factory,
    assetHandler: AssetHandler;
  let poolFactory: PoolFactory,
    poolLogic: PoolLogic,
    poolManagerLogic: PoolManagerLogic,
    poolLogicProxy: PoolLogic,
    poolManagerLogicProxy: PoolManagerLogic,
    fundAddress: string;

  before(async function () {
    [logicOwner, manager, dao, user] = await ethers.getSigners();

    const AssetHandlerLogic = await ethers.getContractFactory("AssetHandler");

    const Governance = await ethers.getContractFactory("Governance");
    let governance = await Governance.deploy();
    console.log("governance deployed to:", governance.address);

    const PoolPerformance = await ethers.getContractFactory("PoolPerformance");
    const poolPerformance = await upgrades.deployProxy(PoolPerformance);
    await poolPerformance.deployed();

    PoolLogic = await ethers.getContractFactory("PoolLogic");
    poolLogic = await PoolLogic.deploy();

    PoolManagerLogic = await ethers.getContractFactory("PoolManagerLogic");
    poolManagerLogic = await PoolManagerLogic.deploy();

    // Initialize Asset Price Consumer

    const assetWeth = { asset: assets.weth, assetType: 0, aggregator: price_feeds.eth };
    const assetUsdt = { asset: assets.usdt, assetType: 0, aggregator: price_feeds.usdt };
    const assetUsdc = { asset: assets.usdc, assetType: 0, aggregator: price_feeds.usdc };
    const assetHandlerInitAssets = [assetWeth, assetUsdt, assetUsdc];

    assetHandler = <AssetHandler>await upgrades.deployProxy(AssetHandlerLogic, [assetHandlerInitAssets]);
    await assetHandler.deployed();
    await assetHandler.setChainlinkTimeout((3600 * 24 * 365).toString()); // 1 year expiry

    PoolFactory = await ethers.getContractFactory("PoolFactory");
    poolFactory = <PoolFactory>(
      await upgrades.deployProxy(PoolFactory, [
        poolLogic.address,
        poolManagerLogic.address,
        assetHandler.address,
        dao.address,
        governance.address,
      ])
    );
    await poolFactory.deployed();

    await poolFactory.setPoolPerformanceAddress(poolPerformance.address);

    const ERC20Guard = await ethers.getContractFactory("ERC20Guard");
    const erc20Guard = await ERC20Guard.deploy();
    erc20Guard.deployed();

    const UniswapV3RouterGuard = await ethers.getContractFactory("UniswapV3RouterGuard");
    const uniswapV3RouterGuard = await UniswapV3RouterGuard.deploy(10, 100); // set slippage 10%
    uniswapV3RouterGuard.deployed();

    await governance.setAssetGuard(0, erc20Guard.address);
    await governance.setContractGuard(uniswapV3.router, uniswapV3RouterGuard.address);

    await poolFactory.setExitFee(5, 1000); // 0.5%
  });

  it("Should be able to get USDC", async function () {
    const IWETH = await artifacts.readArtifact("IWETH");
    WETH = <IWETH>await ethers.getContractAt(IWETH.abi, assets.weth);
    const IERC20 = await artifacts.readArtifact("IERC20");
    USDT = <IERC20>await ethers.getContractAt(IERC20.abi, assets.usdt);
    USDC = <IERC20>await ethers.getContractAt(IERC20.abi, assets.usdc);
    const IV3SwapRouter = await artifacts.readArtifact("IV3SwapRouter");
    UniswapRouter = <IV3SwapRouter>await ethers.getContractAt(IV3SwapRouter.abi, uniswapV3.router);
    // deposit ETH -> WETH
    await WETH.deposit({ value: (10e18).toString() });
    // WETH -> USDT
    let sourceAmount = (5e18).toString();
    await WETH.approve(uniswapV3.router, (5e18).toString());
    const exactInputSingleParams = {
      tokenIn: assets.weth,
      tokenOut: assets.usdc,
      fee: 10000,
      recipient: logicOwner.address,
      amountIn: sourceAmount,
      amountOutMinimum: 0,
      sqrtPriceLimitX96: 0,
    };
    await UniswapRouter.exactInputSingle(exactInputSingleParams);

    // const path =
    //   "0x" +
    //   assets.weth.substring(2) + // source asset
    //   "0001f4" + // fee
    //   assets.usdc.substring(2) + // path asset
    //   "0001f4" + // fee
    //   assets.usdt.substring(2); // destination asset
    // const exactInputParams = {
    //   path: path,
    //   recipient: logicOwner.address,
    //   amountIn: sourceAmount,
    //   amountOutMinimum: 0,
    // };
    // await UniswapRouter.exactInput(exactInputParams);
  });

  it("Should be able to createFund", async function () {
    await poolFactory.createFund(
      false,
      manager.address,
      "Barren Wuffet",
      "Test Fund",
      "DHTF",
      ethers.BigNumber.from("5000"),
      [
        {
          asset: assets.usdc,
          isDeposit: true,
        },
        {
          asset: assets.weth,
          isDeposit: true,
        },
      ],
    );

    let deployedFunds = await poolFactory.getDeployedFunds();
    let deployedFundsLength = deployedFunds.length;
    fundAddress = deployedFunds[deployedFundsLength - 1];
    expect(deployedFundsLength.toString()).to.equal("1");

    let isPool = await poolFactory.isPool(fundAddress);
    expect(isPool).to.be.true;

    let poolManagerLogicAddress = await poolFactory.getLogic(1);
    expect(poolManagerLogicAddress).to.equal(poolManagerLogic.address);

    let poolLogicAddress = await poolFactory.getLogic(2);
    expect(poolLogicAddress).to.equal(poolLogic.address);

    poolLogicProxy = await PoolLogic.attach(fundAddress);
    let poolManagerLogicProxyAddress = await poolLogicProxy.poolManagerLogic();
    poolManagerLogicProxy = await PoolManagerLogic.attach(poolManagerLogicProxyAddress);

    //default assets are supported
    let supportedAssets = await poolManagerLogicProxy.getSupportedAssets();
    let numberOfSupportedAssets = supportedAssets.length;
    expect(numberOfSupportedAssets).to.eq(2);
    expect(await poolManagerLogicProxy.isSupportedAsset(assets.usdc)).to.be.true;
    expect(await poolManagerLogicProxy.isSupportedAsset(assets.weth)).to.be.true;

    //Other assets are not supported
    expect(await poolManagerLogicProxy.isSupportedAsset(assets.usdt)).to.be.false;
  });

  it("should be able to deposit", async function () {
    let totalFundValue = await poolManagerLogicProxy.totalFundValue();
    expect(totalFundValue.toString()).to.equal("0");

    await expect(poolLogicProxy.deposit(assets.usdt, (100e6).toString())).to.be.revertedWith("invalid deposit asset");

    // Approve and deposit 100 USDC
    await USDC.approve(poolLogicProxy.address, (100e6).toString());
    await poolLogicProxy.deposit(assets.usdc, (100e6).toString());

    // Approve and deposit 5 WETH
    await WETH.approve(poolLogicProxy.address, (5e18).toString());
    await poolLogicProxy.deposit(assets.weth, (5e18).toString());
  });

  it("Should be able to approve", async () => {
    const IERC20 = await artifacts.readArtifact("IERC20");
    const iERC20 = new ethers.utils.Interface(IERC20.abi);
    let approveABI = iERC20.encodeFunctionData("approve", [assets.usdc, (100e6).toString()]);
    await expect(poolLogicProxy.connect(manager).execTransaction(assets.usdt, approveABI)).to.be.revertedWith(
      "asset not enabled in pool",
    );

    await expect(poolLogicProxy.connect(manager).execTransaction(assets.usdc, approveABI)).to.be.revertedWith(
      "unsupported spender approval",
    );

    // Approve to swap 100 USDC
    approveABI = iERC20.encodeFunctionData("approve", [uniswapV3.router, (100e6).toString()]);
    await poolLogicProxy.connect(manager).execTransaction(assets.usdc, approveABI);

    // Approve to swap 1 WETH
    approveABI = iERC20.encodeFunctionData("approve", [uniswapV3.router, (1e18).toString()]);
    await poolLogicProxy.connect(manager).execTransaction(assets.weth, approveABI);
  });

  it("should be able to swap tokens - direct swap", async () => {
    const sourceAmount = ethers.BigNumber.from((5e6).toString());
    const minAmountOut = await getMinAmountOut(
      {
        assetHandler: assetHandler,
      } as any,
      ethers.BigNumber.from(sourceAmount),
      USDC.address,
      WETH.address,
    );
    const IV3SwapRouter = await artifacts.readArtifact("IV3SwapRouter");
    const iV3SwapRouter = new ethers.utils.Interface(IV3SwapRouter.abi);
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

  it("should be able to swap tokens - multi swap", async () => {
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
      {
        assetHandler: assetHandler,
      } as any,
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
});
