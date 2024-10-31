import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import hre, { ethers, upgrades } from "hardhat";

import { updateChainlinkAggregators } from "../../testHelpers";
import {
  MockContract,
  PoolFactory,
  PoolLogic,
  TestUSDC,
  TestWETH,
  UniswapV3RouterGuard,
  SlippageAccumulator,
  Governance,
  PoolLogic__factory,
  SwapRouterMock,
  OneInchV6Guard,
  IAggregationRouterV6__factory,
} from "../../../types";
import { Contract, BigNumber, constants } from "ethers";
import { SwapDataStruct } from "../../../types/SlippageAccumulator";
import { utils } from "../../integration/utils/utils";
import { ExactInputParamsStruct } from "../../../types/IV3SwapRouter";
import { Interface } from "ethers/lib/utils";
import { SwapDescriptionStruct } from "../../../types/IAggregationRouterV5";
import { Address } from "../../../deployment/types";

const toETH = (usdcAmount: number) => BigNumber.from(usdcAmount).mul(1e12).div(2000);

const amount = 100e6;

describe("SlippageAccumulator and SlippageAccumulatorUser Tests", () => {
  let manager: SignerWithAddress, investor: SignerWithAddress, dao: SignerWithAddress, user1: SignerWithAddress;
  let uniswapV3RouterGuardImpersonator: SignerWithAddress, oneInchV6GuardImpersonator: SignerWithAddress;
  let poolFactory: PoolFactory;
  let PoolLogicFactory: PoolLogic__factory;
  let governance: Governance;
  let poolLogicProxy: PoolLogic;
  let poolManagerLogic: Address;
  let weth: TestWETH, wethPriceFeed: MockContract;
  let wethAddress: string;
  let usdcProxy: TestUSDC, usdcPriceFeed: MockContract, linkPriceFeed: MockContract;
  let usdcAddress: string;
  let assetHandler: Contract;
  let slippageAccumulator: SlippageAccumulator;
  let uniswapV3RouterGuard: UniswapV3RouterGuard, oneInchV6Guard: OneInchV6Guard;
  let uniswapV2Router: SwapRouterMock, uniswapV3Router: SwapRouterMock, oneInchRouter: SwapRouterMock; // integrating contracts
  let iUniswapV3Router: Interface;
  const IAggregationRouterV6 = new ethers.utils.Interface(IAggregationRouterV6__factory.abi);

  before(async () => {
    [manager, investor, dao, user1] = await ethers.getSigners();

    const TestUSDC = await ethers.getContractFactory("TestUSDC");
    usdcProxy = await TestUSDC.deploy(200_000_000);
    await usdcProxy.deployed();
    usdcAddress = usdcProxy.address;
    const MockContract = await ethers.getContractFactory("MockContract");
    usdcPriceFeed = await MockContract.deploy();
    const TestWETH = await ethers.getContractFactory("TestWETH");
    weth = await TestWETH.deploy(20_000_000);
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

    const uniswapV3SwapRouterArtifact = await hre.artifacts.readArtifact(
      "contracts/interfaces/uniswapV3/IV3SwapRouter.sol:IV3SwapRouter",
    );
    iUniswapV3Router = new ethers.utils.Interface(uniswapV3SwapRouterArtifact.abi);
  });

  beforeEach(async () => {
    const SwapRouterMock = await ethers.getContractFactory("SwapRouterMock");

    // Deploy SlippageAccumulator
    const SlippageAccumulator = await ethers.getContractFactory("SlippageAccumulator");
    slippageAccumulator = <SlippageAccumulator>await SlippageAccumulator.deploy(poolFactory.address, "21600", 5e4); // 6 hours decay time and 5% max cumulative slippage impact
    slippageAccumulator.deployed();

    uniswapV2Router = await SwapRouterMock.deploy();
    uniswapV3Router = await SwapRouterMock.deploy();
    oneInchRouter = await SwapRouterMock.deploy();
    uniswapV2Router.deployed();
    uniswapV3Router.deployed();
    oneInchRouter.deployed();

    const UniswapV3RouterGuard = await ethers.getContractFactory(
      "contracts/guards/contractGuards/uniswapV3/UniswapV3RouterGuard.sol:UniswapV3RouterGuard",
    );
    uniswapV3RouterGuard = <UniswapV3RouterGuard>await UniswapV3RouterGuard.deploy(slippageAccumulator.address);
    uniswapV3RouterGuard.deployed();

    const OneInchV6Guard = await ethers.getContractFactory(
      "contracts/guards/contractGuards/OneInchV6Guard.sol:OneInchV6Guard",
    );
    oneInchV6Guard = <OneInchV6Guard>(
      await OneInchV6Guard.deploy(
        slippageAccumulator.address,
        uniswapV2Router.address,
        uniswapV3Router.address,
        constants.AddressZero,
      )
    );
    oneInchV6Guard.deployed();

    [uniswapV3RouterGuardImpersonator, oneInchV6GuardImpersonator] = await utils.impersonateAccounts([
      uniswapV3RouterGuard.address,
      oneInchV6Guard.address,
    ]);

    const ERC20Guard = await ethers.getContractFactory("contracts/guards/assetGuards/ERC20Guard.sol:ERC20Guard");
    const erc20Guard = await ERC20Guard.deploy();
    erc20Guard.deployed();

    await governance.setAssetGuard(0, erc20Guard.address);
    await governance.setContractGuard(uniswapV3Router.address, uniswapV3RouterGuard.address);
    await governance.setContractGuard(oneInchRouter.address, oneInchV6Guard.address);

    await poolFactory.createFund(false, manager.address, "String0", "String1", "String3", 0, 0, [
      { asset: usdcAddress, isDeposit: true },
      { asset: wethAddress, isDeposit: true },
    ]);
    const pools = await poolFactory.getDeployedFunds();
    poolLogicProxy = PoolLogicFactory.attach(pools[0]);
    poolManagerLogic = await poolLogicProxy.poolManagerLogic();

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

    await approveUSDCToRouter(uniswapV3Router.address, ethers.constants.MaxUint256);
    await approveUSDCToRouter(oneInchRouter.address, ethers.constants.MaxUint256);
  });

  async function approveUSDCToRouter(routerAddress: string, amount: BigNumber | number) {
    await poolLogicProxy
      .connect(manager)
      .execTransaction(usdcProxy.address, usdcProxy.interface.encodeFunctionData("approve", [routerAddress, amount]));
  }

  describe("SlippageAccumulator Tests", () => {
    it("should revert if high slippage impact in a single trade", async () => {
      // Creating swap data with 5% slippage. This should revert.
      const swapData: SwapDataStruct = {
        srcAsset: usdcAddress,
        dstAsset: wethAddress,
        srcAmount: amount,
        dstAmount: toETH(amount).mul(95).div(100),
      };

      await expect(
        slippageAccumulator
          .connect(uniswapV3RouterGuardImpersonator)
          .updateSlippageImpact(poolManagerLogic, uniswapV3Router.address, swapData),
      ).to.be.revertedWith("slippage impact exceeded");
    });

    it("should revert if high slippage impact after multiple trades", async () => {
      // Creating swap data with 2% slippage. This should not revert.
      const swapData: SwapDataStruct = {
        srcAsset: usdcAddress,
        dstAsset: wethAddress,
        srcAmount: amount,
        dstAmount: toETH(amount).mul(98).div(100),
      };

      await slippageAccumulator
        .connect(uniswapV3RouterGuardImpersonator)
        .updateSlippageImpact(poolManagerLogic, uniswapV3Router.address, swapData);

      // Performing the same swap for the second time. Total slippage = 4%
      await slippageAccumulator
        .connect(uniswapV3RouterGuardImpersonator)
        .updateSlippageImpact(poolManagerLogic, uniswapV3Router.address, swapData);

      // Performing the same swap for the third time. Total slippage = 6%. This should revert.
      await expect(
        slippageAccumulator
          .connect(uniswapV3RouterGuardImpersonator)
          .updateSlippageImpact(poolManagerLogic, uniswapV3Router.address, swapData),
      ).to.be.revertedWith("slippage impact exceeded");
    });

    it("should revert if high slippage impact after multiple trades using different protocols", async () => {
      // Creating swap data with 2% slippage. This should not revert.
      const swapDataUniswapV2: SwapDataStruct = {
        srcAsset: usdcAddress,
        dstAsset: wethAddress,
        srcAmount: amount,
        dstAmount: toETH(amount).mul(98).div(100),
      };

      // Performing a swap using Uniswap V3. Slippage = 2%.
      await slippageAccumulator
        .connect(uniswapV3RouterGuardImpersonator)
        .updateSlippageImpact(poolManagerLogic, uniswapV3Router.address, swapDataUniswapV2);

      const swapDataUniswapV3: SwapDataStruct = {
        srcAsset: usdcAddress,
        dstAsset: wethAddress,
        srcAmount: amount,
        dstAmount: toETH(amount).mul(98).div(100),
      };

      // Performing a swap using Uniswap V3 for the second time. Total slippage = 4%.
      await slippageAccumulator
        .connect(uniswapV3RouterGuardImpersonator)
        .updateSlippageImpact(poolManagerLogic, uniswapV3Router.address, swapDataUniswapV3);

      const swapDataOneInchV4: SwapDataStruct = {
        srcAsset: usdcAddress,
        dstAsset: wethAddress,
        srcAmount: amount,
        dstAmount: toETH(amount).mul(98).div(100),
      };

      // Performing a swap using 1inch. Total slippage = 6%. This should revert.
      await expect(
        slippageAccumulator
          .connect(oneInchV6GuardImpersonator)
          .updateSlippageImpact(poolManagerLogic, oneInchRouter.address, swapDataOneInchV4),
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
      };

      // Performing a swap using Uniswap V3. Slippage = 2%.
      await slippageAccumulator
        .connect(uniswapV3RouterGuardImpersonator)
        .updateSlippageImpact(poolManagerLogic, uniswapV3Router.address, swapDataUniswapV2);

      const swapDataUniswapV3: SwapDataStruct = {
        srcAsset: usdcAddress,
        dstAsset: wethAddress,
        srcAmount: amount,
        dstAmount: toETH(amount).mul(98).div(100),
      };

      // Performing a swap using Uniswap V3 for the second time. Total slippage = 4%.
      await slippageAccumulator
        .connect(uniswapV3RouterGuardImpersonator)
        .updateSlippageImpact(poolManagerLogic, uniswapV3Router.address, swapDataUniswapV3);

      const swapDataOneInchV4: SwapDataStruct = {
        srcAsset: usdcAddress,
        dstAsset: wethAddress,
        srcAmount: amount,
        dstAmount: toETH(amount).mul(98).div(100),
      };

      await utils.increaseTime(6 * 3600); // Increase time by 6 hours.

      const slippageImpact = await slippageAccumulator.getCumulativeSlippageImpact(poolManagerLogicAddress);

      // Cumulative slippage should be 0% after decayTime.
      expect(slippageImpact).to.equal(ethers.constants.Zero, "Slippage impact not 0 after decayTime period (6 hours)");

      await slippageAccumulator
        .connect(oneInchV6GuardImpersonator)
        .updateSlippageImpact(poolManagerLogic, oneInchRouter.address, swapDataOneInchV4);
    });

    it("should revert if the `to` (external contract / router) address is wrong", async () => {
      const swapDataUniswapV2: SwapDataStruct = {
        srcAsset: usdcAddress,
        dstAsset: wethAddress,
        srcAmount: amount,
        dstAmount: toETH(amount).mul(98).div(100),
      };

      await expect(
        slippageAccumulator
          .connect(uniswapV3RouterGuardImpersonator)
          .updateSlippageImpact(poolManagerLogic, manager.address, swapDataUniswapV2),
      ).to.be.revertedWith("Not authorised guard");
    });

    it("should revert if the caller is not a guard", async () => {
      const swapDataUniswapV2: SwapDataStruct = {
        srcAsset: usdcAddress,
        dstAsset: wethAddress,
        srcAmount: amount,
        dstAmount: toETH(amount).mul(98).div(100),
      };

      await expect(
        slippageAccumulator
          .connect(manager)
          .updateSlippageImpact(poolManagerLogic, uniswapV3Router.address, swapDataUniswapV2),
      ).to.be.revertedWith("Not authorised guard");
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

  describe("SlippageAccumulatorUser Tests", () => {
    async function transferTokensForSwap(
      routerAddress: string,
      srcAmount: BigNumber | number,
      dstAmount: BigNumber | number,
    ) {
      await usdcProxy.connect(manager).transfer(poolLogicProxy.address, srcAmount);
      await weth.connect(manager).transfer(routerAddress, dstAmount);
    }

    it("should revert if high slippage impact in a single trade", async () => {
      const destAmount = toETH(amount).mul(95).div(100);

      const path =
        "0x" +
        usdcAddress.substring(2) + // source asset
        "000bb8" + // fee
        wethAddress.substring(2) + // path asset
        "000bb8" + // fee
        wethAddress.substring(2); // destination asset
      const exactInputParams: ExactInputParamsStruct = {
        path: path,
        recipient: poolLogicProxy.address,
        amountIn: amount,
        amountOutMinimum: destAmount,
      };
      const swapABI = iUniswapV3Router.encodeFunctionData("exactInput", [exactInputParams]);

      // Transfer enough tokens to the pool and uniswapV3Router for the swap to go through.
      await transferTokensForSwap(uniswapV3Router.address, amount, destAmount);

      await expect(
        poolLogicProxy.connect(manager).execTransaction(uniswapV3Router.address, swapABI),
      ).to.be.revertedWith("slippage impact exceeded");
    });

    it("should revert if high slippage impact after multiple trades", async () => {
      // Creating swap data with 2% slippage. This should not revert.
      const destAmount = toETH(amount).mul(98).div(100);
      const path =
        "0x" +
        usdcAddress.substring(2) + // source asset
        "000bb8" + // fee
        wethAddress.substring(2) + // path asset
        "000bb8" + // fee
        wethAddress.substring(2); // destination asset
      const exactInputParams: ExactInputParamsStruct = {
        path: path,
        recipient: poolLogicProxy.address,
        amountIn: amount,
        amountOutMinimum: destAmount,
      };

      await transferTokensForSwap(uniswapV3Router.address, amount, destAmount);

      await poolLogicProxy
        .connect(manager)
        .execTransaction(
          uniswapV3Router.address,
          iUniswapV3Router.encodeFunctionData("exactInput", [exactInputParams]),
        );

      await transferTokensForSwap(uniswapV3Router.address, amount, destAmount);

      await poolLogicProxy
        .connect(manager)
        .execTransaction(
          uniswapV3Router.address,
          iUniswapV3Router.encodeFunctionData("exactInput", [exactInputParams]),
        );

      await transferTokensForSwap(uniswapV3Router.address, amount, destAmount);

      // Performing the same swap for the third time. Total slippage = 6%. This should revert.
      await expect(
        poolLogicProxy
          .connect(manager)
          .execTransaction(
            uniswapV3Router.address,
            iUniswapV3Router.encodeFunctionData("exactInput", [exactInputParams]),
          ),
      ).to.be.revertedWith("slippage impact exceeded");
    });

    it("should revert if high slippage impact after multiple trades using different protocols", async () => {
      // Creating swap data with 2% slippage. This should not revert.
      const destAmount = toETH(amount).mul(98).div(100);
      const path =
        "0x" +
        usdcAddress.substring(2) + // source asset
        "000bb8" + // fee
        wethAddress.substring(2) + // path asset
        "000bb8" + // fee
        wethAddress.substring(2); // destination asset
      const exactInputParams: ExactInputParamsStruct = {
        path: path,
        recipient: poolLogicProxy.address,
        amountIn: amount,
        amountOutMinimum: destAmount,
      };

      await transferTokensForSwap(uniswapV3Router.address, amount, destAmount);

      await poolLogicProxy
        .connect(manager)
        .execTransaction(
          uniswapV3Router.address,
          iUniswapV3Router.encodeFunctionData("exactInput", [exactInputParams]),
        );

      await transferTokensForSwap(uniswapV3Router.address, amount, destAmount);

      await poolLogicProxy
        .connect(manager)
        .execTransaction(
          uniswapV3Router.address,
          iUniswapV3Router.encodeFunctionData("exactInput", [exactInputParams]),
        );

      const swapDataOneInchV6: SwapDescriptionStruct = {
        srcToken: usdcAddress,
        dstToken: wethAddress,
        srcReceiver: poolLogicProxy.address,
        dstReceiver: poolLogicProxy.address,
        amount: amount,
        minReturnAmount: destAmount,
        flags: 0,
      };

      const swapDataOneInchV6Encoded = IAggregationRouterV6.encodeFunctionData("swap", [
        poolLogicProxy.address,
        swapDataOneInchV6,
        "0x",
      ]);

      await transferTokensForSwap(oneInchRouter.address, amount, destAmount);

      // Performing a swap using 1inch. Total slippage = 6%. This should revert.
      await expect(
        poolLogicProxy.connect(manager).execTransaction(oneInchRouter.address, swapDataOneInchV6Encoded),
      ).to.be.revertedWith("slippage impact exceeded");
    });
  });
});
