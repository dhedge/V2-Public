import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { ethers, upgrades } from "hardhat";

import { updateChainlinkAggregators } from "../testHelpers";
import {
  MockContract,
  PoolFactory,
  PoolLogic,
  TestUSDC,
  TestWETH,
  UniswapV2RouterGuard,
  UniswapV3RouterGuard,
  SlippageAccumulator,
  OneInchV5Guard,
  Governance,
  PoolLogic__factory,
} from "../../types";
import { Contract, BigNumber } from "ethers";
import { SwapDataStruct } from "../../types/SlippageAccumulator";
import { utils } from "../integration/utils/utils";

const toETH = (usdcAmount: number) => BigNumber.from(usdcAmount).mul(1e12).div(2000);

const amount = 100e6;

describe("Slippage Accumulator Tests", () => {
  let manager: SignerWithAddress, investor: SignerWithAddress, dao: SignerWithAddress, user1: SignerWithAddress;
  let uniswapV2RouterGuardImpersonator: SignerWithAddress,
    uniswapV3RouterGuardImpersonator: SignerWithAddress,
    oneInchV5GuardImpersonator: SignerWithAddress;
  let poolFactory: PoolFactory;
  let PoolLogicFactory: PoolLogic__factory;
  let governance: Governance;
  let poolLogicProxy: PoolLogic;
  let weth: TestWETH, wethPriceFeed: MockContract;
  let wethAddress: string;
  let usdcProxy: TestUSDC, usdcPriceFeed: MockContract, linkPriceFeed: MockContract;
  let usdcAddress: string;
  let assetHandler: Contract;
  let slippageAccumulator: SlippageAccumulator;
  let uniswapV2RouterGuard: UniswapV2RouterGuard,
    uniswapV3RouterGuard: UniswapV3RouterGuard,
    oneInchV5Guard: OneInchV5Guard;
  let uniswapV2Router: MockContract, uniswapV3Router: MockContract, oneInchRouter: MockContract; // integrating contracts

  before(async () => {
    [manager, investor, dao, user1] = await ethers.getSigners();

    const TestUSDC = await ethers.getContractFactory("TestUSDC");
    usdcProxy = await TestUSDC.deploy(20_000_000);
    await usdcProxy.deployed();
    usdcAddress = usdcProxy.address;
    const MockContract = await ethers.getContractFactory("MockContract");
    usdcPriceFeed = await MockContract.deploy();
    const TestWETH = await ethers.getContractFactory("TestWETH");
    weth = await TestWETH.deploy(2_000_000);
    await weth.deployed();
    wethAddress = weth.address;
    wethPriceFeed = await MockContract.deploy();
    linkPriceFeed = await MockContract.deploy();

    PoolLogicFactory = await ethers.getContractFactory("PoolLogic");
    const poolLogic = await PoolLogicFactory.deploy();

    const PoolManagerLogic = await ethers.getContractFactory("PoolManagerLogic");
    const poolManagerLogic = await PoolManagerLogic.deploy();

    const AssetHandlerLogic = await ethers.getContractFactory(
      "contracts/priceAggregators/AssetHandler.sol:AssetHandler",
    );
    const assetHandlerInitAssets = [
      { asset: usdcAddress, assetType: 0, aggregator: usdcPriceFeed.address },
      { asset: wethAddress, assetType: 0, aggregator: wethPriceFeed.address },
    ];
    assetHandler = await upgrades.deployProxy(AssetHandlerLogic, [assetHandlerInitAssets]);
    await assetHandler.deployed();

    const Governance = await ethers.getContractFactory("Governance");
    governance = await Governance.deploy();

    const PoolFactory = await ethers.getContractFactory("PoolFactory");
    poolFactory = <PoolFactory>(
      await upgrades.deployProxy(PoolFactory, [
        poolLogic.address,
        poolManagerLogic.address,
        assetHandler.address,
        dao.address,
        governance.address,
      ])
    );
  });

  beforeEach(async () => {
    const MockContract = await ethers.getContractFactory("MockContract");

    // Deploy SlippageAccumulator
    const SlippageAccumulator = await ethers.getContractFactory("SlippageAccumulator");
    slippageAccumulator = <SlippageAccumulator>await SlippageAccumulator.deploy(poolFactory.address, "21600", 5e4); // 6 hours decay time and 5% max cumulative slippage impact
    slippageAccumulator.deployed();

    uniswapV2Router = await MockContract.deploy();
    uniswapV3Router = await MockContract.deploy();
    oneInchRouter = await MockContract.deploy();
    uniswapV2Router.deployed();
    uniswapV3Router.deployed();
    oneInchRouter.deployed();

    const UniswapV2RouterGuard = await ethers.getContractFactory(
      "contracts/guards/contractGuards/UniswapV2RouterGuard.sol:UniswapV2RouterGuard",
    );
    uniswapV2RouterGuard = <UniswapV2RouterGuard>await UniswapV2RouterGuard.deploy(slippageAccumulator.address);
    uniswapV2RouterGuard.deployed();

    const UniswapV3RouterGuard = await ethers.getContractFactory(
      "contracts/guards/contractGuards/uniswapV3/UniswapV3RouterGuard.sol:UniswapV3RouterGuard",
    );
    uniswapV3RouterGuard = <UniswapV3RouterGuard>await UniswapV3RouterGuard.deploy(slippageAccumulator.address);
    uniswapV3RouterGuard.deployed();

    const OneInchV5Guard = await ethers.getContractFactory(
      "contracts/guards/contractGuards/OneInchV5Guard.sol:OneInchV5Guard",
    );
    oneInchV5Guard = <OneInchV5Guard>await OneInchV5Guard.deploy(slippageAccumulator.address);
    oneInchV5Guard.deployed();

    [uniswapV2RouterGuardImpersonator, uniswapV3RouterGuardImpersonator, oneInchV5GuardImpersonator] =
      await utils.impersonateAccounts([
        uniswapV2RouterGuard.address,
        uniswapV3RouterGuard.address,
        oneInchV5Guard.address,
      ]);

    const ERC20Guard = await ethers.getContractFactory("contracts/guards/assetGuards/ERC20Guard.sol:ERC20Guard");
    const erc20Guard = await ERC20Guard.deploy();
    erc20Guard.deployed();

    await governance.setAssetGuard(0, erc20Guard.address);
    await governance.setContractGuard(uniswapV2Router.address, uniswapV2RouterGuard.address);
    await governance.setContractGuard(uniswapV3Router.address, uniswapV3RouterGuard.address);
    await governance.setContractGuard(oneInchRouter.address, oneInchV5Guard.address);

    await poolFactory.createFund(false, manager.address, "String0", "String1", "String3", 0, 0, [
      { asset: usdcAddress, isDeposit: true },
      { asset: wethAddress, isDeposit: true },
    ]);
    const pools = await poolFactory.getDeployedFunds();
    poolLogicProxy = PoolLogicFactory.attach(pools[0]);

    await updateChainlinkAggregators(usdcPriceFeed, wethPriceFeed, linkPriceFeed);

    await usdcProxy.connect(manager).approve(poolLogicProxy.address, 2000000e6);

    await usdcProxy.transfer(investor.address, 1000000e6);
    await usdcProxy.connect(investor).approve(poolLogicProxy.address, 1000000e6);
    await usdcProxy.transfer(user1.address, 1000000e6);
    await usdcProxy.connect(user1).approve(poolLogicProxy.address, 1000000e6);

    await weth.connect(manager).approve(poolLogicProxy.address, ethers.utils.parseUnits("100", 18));
    await weth.connect(manager).transfer(investor.address, ethers.utils.parseUnits("100", 18));
    await weth.connect(investor).approve(poolLogicProxy.address, ethers.utils.parseUnits("100", 18));
    await weth.connect(manager).transfer(user1.address, ethers.utils.parseUnits("100", 18));
    await weth.connect(user1).approve(poolLogicProxy.address, ethers.utils.parseUnits("100", 18));
  });

  it("should revert if high slippage impact in a single trade", async () => {
    // Creating swap data with 5% slippage. This should revert.
    const swapData: SwapDataStruct = {
      srcAsset: usdcAddress,
      dstAsset: wethAddress,
      srcAmount: amount,
      dstAmount: toETH(amount).mul(95).div(100),
      to: uniswapV2Router.address,
      poolManagerLogic: await poolLogicProxy.poolManagerLogic(),
    };

    await expect(
      slippageAccumulator.connect(uniswapV2RouterGuardImpersonator).updateSlippageImpact(swapData),
    ).to.be.revertedWith("slippage impact exceeded");
  });

  it("should revert if high slippage impact after multiple trades", async () => {
    // Creating swap data with 2% slippage. This should not revert.
    const swapData: SwapDataStruct = {
      srcAsset: usdcAddress,
      dstAsset: wethAddress,
      srcAmount: amount,
      dstAmount: toETH(amount).mul(98).div(100),
      to: uniswapV2Router.address,
      poolManagerLogic: await poolLogicProxy.poolManagerLogic(),
    };

    await slippageAccumulator.connect(uniswapV2RouterGuardImpersonator).updateSlippageImpact(swapData);

    // Performing the same swap for the second time. Total slippage = 4%
    await slippageAccumulator.connect(uniswapV2RouterGuardImpersonator).updateSlippageImpact(swapData);

    // Performing the same swap for the third time. Total slippage = 6%. This should revert.
    await expect(
      slippageAccumulator.connect(uniswapV2RouterGuardImpersonator).updateSlippageImpact(swapData),
    ).to.be.revertedWith("slippage impact exceeded");
  });

  it("should revert if high slippage impact after multiple trades using different protocols", async () => {
    const poolManagerLogicAddress = await poolLogicProxy.poolManagerLogic();

    // Creating swap data with 2% slippage. This should not revert.
    const swapDataUniswapV2: SwapDataStruct = {
      srcAsset: usdcAddress,
      dstAsset: wethAddress,
      srcAmount: amount,
      dstAmount: toETH(amount).mul(98).div(100),
      to: uniswapV2Router.address,
      poolManagerLogic: poolManagerLogicAddress,
    };

    // Performing a swap using Uniswap V2. Slippage = 2%.
    await slippageAccumulator.connect(uniswapV2RouterGuardImpersonator).updateSlippageImpact(swapDataUniswapV2);

    const swapDataUniswapV3: SwapDataStruct = {
      srcAsset: usdcAddress,
      dstAsset: wethAddress,
      srcAmount: amount,
      dstAmount: toETH(amount).mul(98).div(100),
      to: uniswapV3Router.address,
      poolManagerLogic: poolManagerLogicAddress,
    };

    // Performing a swap using Uniswap V3 for the second time. Total slippage = 4%.
    await slippageAccumulator.connect(uniswapV3RouterGuardImpersonator).updateSlippageImpact(swapDataUniswapV3);

    const swapDataOneInchV4: SwapDataStruct = {
      srcAsset: usdcAddress,
      dstAsset: wethAddress,
      srcAmount: amount,
      dstAmount: toETH(amount).mul(98).div(100),
      to: oneInchRouter.address,
      poolManagerLogic: poolManagerLogicAddress,
    };

    // Performing a swap using 1inch. Total slippage = 6%. This should revert.
    await expect(
      slippageAccumulator.connect(oneInchV5GuardImpersonator).updateSlippageImpact(swapDataOneInchV4),
    ).to.be.revertedWith("slippage impact exceeded");
  });

  it("should not revert when slippage due to a trade is under threshold (5%) after decayTime (6 hours)", async () => {
    const poolManagerLogicAddress = await poolLogicProxy.poolManagerLogic();

    // Creating swap data with 2% slippage. This should not revert.
    const swapDataUniswapV2: SwapDataStruct = {
      srcAsset: usdcAddress,
      dstAsset: wethAddress,
      srcAmount: amount,
      dstAmount: toETH(amount).mul(98).div(100),
      to: uniswapV2Router.address,
      poolManagerLogic: poolManagerLogicAddress,
    };

    // Performing a swap using Uniswap V2. Slippage = 2%.
    await slippageAccumulator.connect(uniswapV2RouterGuardImpersonator).updateSlippageImpact(swapDataUniswapV2);

    const swapDataUniswapV3: SwapDataStruct = {
      srcAsset: usdcAddress,
      dstAsset: wethAddress,
      srcAmount: amount,
      dstAmount: toETH(amount).mul(98).div(100),
      to: uniswapV3Router.address,
      poolManagerLogic: poolManagerLogicAddress,
    };

    // Performing a swap using Uniswap V3 for the second time. Total slippage = 4%.
    await slippageAccumulator.connect(uniswapV3RouterGuardImpersonator).updateSlippageImpact(swapDataUniswapV3);

    const swapDataOneInchV4: SwapDataStruct = {
      srcAsset: usdcAddress,
      dstAsset: wethAddress,
      srcAmount: amount,
      dstAmount: toETH(amount).mul(98).div(100),
      to: oneInchRouter.address,
      poolManagerLogic: poolManagerLogicAddress,
    };

    await utils.increaseTime(6 * 3600); // Increase time by 6 hours.

    const slippageImpact = await slippageAccumulator.getCumulativeSlippageImpact(poolManagerLogicAddress);

    // Cumulative slippage should be 0% after decayTime.
    expect(slippageImpact).to.equal(ethers.constants.Zero, "Slippage impact not 0 after decayTime period (6 hours)");

    await slippageAccumulator.connect(oneInchV5GuardImpersonator).updateSlippageImpact(swapDataOneInchV4);
  });

  it("should revert if the `to` (external contract / router) address is wrong", async () => {
    const swapDataUniswapV2: SwapDataStruct = {
      srcAsset: usdcAddress,
      dstAsset: wethAddress,
      srcAmount: amount,
      dstAmount: toETH(amount).mul(98).div(100),
      to: manager.address,
      poolManagerLogic: await poolLogicProxy.poolManagerLogic(),
    };

    await expect(
      slippageAccumulator.connect(uniswapV2RouterGuardImpersonator).updateSlippageImpact(swapDataUniswapV2),
    ).to.be.revertedWith("Not authorised guard");
  });

  it("should revert if the caller is not a guard", async () => {
    const swapDataUniswapV2: SwapDataStruct = {
      srcAsset: usdcAddress,
      dstAsset: wethAddress,
      srcAmount: amount,
      dstAmount: toETH(amount).mul(98).div(100),
      to: uniswapV2Router.address,
      poolManagerLogic: await poolLogicProxy.poolManagerLogic(),
    };

    await expect(slippageAccumulator.connect(manager).updateSlippageImpact(swapDataUniswapV2)).to.be.revertedWith(
      "Not authorised guard",
    );
  });

  it("should be able to set new decayTime", async () => {
    const newDecayTime = 12 * 3600;

    // Setting the decayTime to 12 hours.
    await slippageAccumulator.setDecayTime(newDecayTime);

    expect(await slippageAccumulator.decayTime()).to.equal(newDecayTime, "Incorrect new decayTime");
  });

  it("should not be able to set new decayTime if not owner", async () => {
    // Setting the decayTime to 12 hours as manager. This should revert.
    await expect(slippageAccumulator.connect(investor).setDecayTime(12 * 3600)).to.be.revertedWith(
      "Ownable: caller is not the owner",
    );
  });

  it("should be able to set new max cumulative slippage", async () => {
    // New max cumulative slippage is 10%.
    const newMaxCumulativeSlippage = 10e4;

    // Setting the decayTime to 12 hours.
    await slippageAccumulator.setMaxCumulativeSlippage(newMaxCumulativeSlippage);

    expect(await slippageAccumulator.maxCumulativeSlippage()).to.equal(
      newMaxCumulativeSlippage,
      "Incorrect new max cumulative slippage",
    );
  });

  it("should not be able to set new decayTime if not owner", async () => {
    // Setting the decayTime to 12 hours as manager. This should revert.
    await expect(slippageAccumulator.connect(investor).setMaxCumulativeSlippage(10e4)).to.be.revertedWith(
      "Ownable: caller is not the owner",
    );
  });
});
