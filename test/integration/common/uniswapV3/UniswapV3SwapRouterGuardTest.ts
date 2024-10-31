import hre, { ethers } from "hardhat";
import { expect } from "chai";

import { checkAlmostSame } from "../../../testHelpers";
import {
  IERC20__factory,
  IMulticallExtended__factory,
  IV3SwapRouter__factory,
  PoolFactory,
  PoolLogic,
  PoolManagerLogic,
  MockContract,
} from "../../../../types";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { createFund } from "../../utils/createFund";
import { getAccountToken } from "../../utils/getAccountTokens";
import { BigNumber, constants } from "ethers";
import { deployContracts, IDeployments, NETWORK } from "../../utils/deployContracts/deployContracts";
import { getMinAmountOut } from "../../utils/getMinAmountOut";
import { utils } from "../../utils/utils";
import { encodePath, FeeAmount } from "../../utils/uniswap";

interface IUniswapV3SwapRouterGuardTestParameter {
  network: NETWORK;
  uniswapV3: {
    factory: string;
    router: string;
    nonfungiblePositionManager: string;
  };
  pair: {
    fee: number;
    token0: string;
    token1: string;
    amount0: BigNumber;
    amount1: BigNumber;
    token0Slot: number;
    token1Slot: number;
  };
  // tokens passed for this pair should be added in AssetHandler during `deployContracts`
  noDirectPoolPair: {
    tokenIn: string;
    tokenIntermediate: string;
    tokenOut: string;
    amountInMax: BigNumber; // can be any big value, out of scope for suite use case
    amountOut: BigNumber; // how much exactly we want to receive after the swap
    tokenInSlot: number;
  };
}

export const uniswapV3SwapRouterGuardTest = (params: IUniswapV3SwapRouterGuardTestParameter) => {
  const { network, uniswapV3, pair, noDirectPoolPair } = params;

  describe("Uniswap V3 Swap Router Test", function () {
    let deployments: IDeployments;
    let logicOwner: SignerWithAddress, manager: SignerWithAddress, anon: SignerWithAddress;
    let poolFactory: PoolFactory, poolLogicProxy: PoolLogic, poolManagerLogicProxy: PoolManagerLogic;
    let evilPoolManager: MockContract;
    const iERC20 = new ethers.utils.Interface(IERC20__factory.abi);
    const IV3SwapRouter = new ethers.utils.Interface(IV3SwapRouter__factory.abi);
    const iMulticall = new ethers.utils.Interface(IMulticallExtended__factory.abi);

    utils.beforeAfterReset(beforeEach, afterEach);

    before(async function () {
      [logicOwner, manager, anon] = await ethers.getSigners();

      deployments = await deployContracts(network);
      poolFactory = deployments.poolFactory;
      const funds = await createFund(poolFactory, logicOwner, manager, [
        { asset: pair.token0, isDeposit: true },
        { asset: pair.token1, isDeposit: true },
      ]);
      poolLogicProxy = funds.poolLogicProxy;
      poolManagerLogicProxy = funds.poolManagerLogicProxy;

      const mockFactory = await ethers.getContractFactory("MockContract");
      evilPoolManager = await mockFactory.deploy();
      await evilPoolManager.deployed();

      await getAccountToken(pair.amount0.mul(3), logicOwner.address, pair.token0, pair.token0Slot);
      await getAccountToken(pair.amount1.mul(3), logicOwner.address, pair.token1, pair.token1Slot);

      await (
        await ethers.getContractAt("@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20", pair.token0)
      ).approve(poolLogicProxy.address, pair.amount0.mul(3));
      await poolLogicProxy.deposit(pair.token0, pair.amount0.mul(3));
      await (
        await ethers.getContractAt("@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20", pair.token1)
      ).approve(poolLogicProxy.address, pair.amount1.mul(3));
      await poolLogicProxy.deposit(pair.token1, pair.amount1.mul(3));

      let approveABI = iERC20.encodeFunctionData("approve", [uniswapV3.router, pair.amount0.mul(3)]);
      await poolLogicProxy.connect(manager).execTransaction(pair.token0, approveABI);
      approveABI = iERC20.encodeFunctionData("approve", [uniswapV3.router, pair.amount1.mul(3)]);
      await poolLogicProxy.connect(manager).execTransaction(pair.token1, approveABI);

      await poolFactory.setExitCooldown(0);
    });

    it("Should be able to swap token0 to token1", async () => {
      const minAmountOut = await getMinAmountOut(deployments.assetHandler, pair.amount0, pair.token0, pair.token1);

      const exactInputSingleCalldata = IV3SwapRouter.encodeFunctionData("exactInputSingle", [
        [
          pair.token0, // from
          pair.token1, // to
          pair.fee, // 0.05% fee
          poolLogicProxy.address,
          pair.amount0,
          minAmountOut,
          0,
        ],
      ]);

      const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();
      await poolLogicProxy.connect(manager).execTransaction(uniswapV3.router, exactInputSingleCalldata);
      const totalFundValueAfter = await poolManagerLogicProxy.totalFundValue();

      checkAlmostSame(totalFundValueAfter, totalFundValueBefore);
    });

    it("Should be able to swap token1 to token0", async () => {
      const minAmountOut = await getMinAmountOut(deployments.assetHandler, pair.amount1, pair.token1, pair.token0);

      const exactInputSingleCalldata = IV3SwapRouter.encodeFunctionData("exactInputSingle", [
        [
          pair.token1, // from
          pair.token0, // to
          pair.fee, // 0.05% fee
          poolLogicProxy.address,
          pair.amount1,
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
      const minAmountOut = await getMinAmountOut(deployments.assetHandler, pair.amount1, pair.token1, pair.token0);

      const exactInputSingleCalldata = IV3SwapRouter.encodeFunctionData("exactInputSingle", [
        [
          pair.token1, // from
          pair.token0, // to
          pair.fee, // 0.05% fee
          poolLogicProxy.address,
          pair.amount1,
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

    it("should not swap into unsupported token when using exactOutput", async () => {
      const { tokenIn, tokenInSlot, tokenIntermediate, tokenOut, amountInMax, amountOut } = noDirectPoolPair;

      // Creating a pool with only single asset supported, which we will swap further on
      const { poolLogicProxy } = await createFund(poolFactory, logicOwner, manager, [
        { asset: tokenIn, isDeposit: true },
      ]);
      await getAccountToken(amountInMax, logicOwner.address, tokenIn, tokenInSlot);
      await (
        await ethers.getContractAt("@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20", tokenIn)
      ).approve(poolLogicProxy.address, amountInMax);
      await poolLogicProxy.deposit(tokenIn, amountInMax);
      await poolLogicProxy
        .connect(manager)
        .execTransaction(tokenIn, iERC20.encodeFunctionData("approve", [uniswapV3.router, amountInMax]));

      const swapPath = [tokenIn, tokenIntermediate, tokenOut].reverse();
      const fees = new Array(swapPath.length - 1).fill(FeeAmount.MEDIUM); // fees doesn't matter
      const path = encodePath(swapPath, fees);
      const exactOutputTxData = IV3SwapRouter.encodeFunctionData("exactOutput", [
        [path, poolLogicProxy.address, amountOut, amountInMax],
      ]);
      await expect(
        poolLogicProxy.connect(manager).execTransaction(uniswapV3.router, exactOutputTxData),
      ).to.be.revertedWith("unsupported destination asset");
    });

    it("should revert in case of high cumulative slippage impact", async () => {
      await deployments.slippageAccumulator.setMaxCumulativeSlippage(1e2); // 0.01%

      const minAmountOut = await getMinAmountOut(deployments.assetHandler, pair.amount0, pair.token0, pair.token1);

      const exactInputSingleCalldata = IV3SwapRouter.encodeFunctionData("exactInputSingle", [
        [
          pair.token0, // from
          pair.token1, // to
          pair.fee, // 0.05% fee
          poolLogicProxy.address,
          pair.amount0,
          minAmountOut,
          0,
        ],
      ]);

      await expect(
        poolLogicProxy.connect(manager).execTransaction(uniswapV3.router, exactInputSingleCalldata),
      ).to.be.revertedWith("slippage impact exceeded");
    });

    it("should not revert 6 hours (decay time) after high slippage accumulation", async () => {
      await deployments.slippageAccumulator.setMaxCumulativeSlippage(1e3); // 0.1%

      const minAmountOut = await getMinAmountOut(deployments.assetHandler, pair.amount0, pair.token0, pair.token1);

      const exactInputSingleCalldata = IV3SwapRouter.encodeFunctionData("exactInputSingle", [
        [
          pair.token0, // from
          pair.token1, // to
          pair.fee, // 0.05% fee
          poolLogicProxy.address,
          pair.amount0,
          minAmountOut,
          0,
        ],
      ]);

      await poolLogicProxy.connect(manager).execTransaction(uniswapV3.router, exactInputSingleCalldata);
      await expect(
        poolLogicProxy.connect(manager).execTransaction(uniswapV3.router, exactInputSingleCalldata),
      ).to.be.revertedWith("slippage impact exceeded");

      await utils.increaseTime(6 * 3600); // Skipping ahead by 6 hours.

      // This call should not revert.
      await poolLogicProxy.connect(manager).execTransaction(uniswapV3.router, exactInputSingleCalldata);
    });

    it("should revert if caller is not the manager but affects the pool of some manager", async () => {
      const minAmountOut = await getMinAmountOut(deployments.assetHandler, pair.amount0, pair.token0, pair.token1);

      const exactInputSingleCalldata = IV3SwapRouter.encodeFunctionData("exactInputSingle", [
        [
          pair.token0, // from
          pair.token1, // to
          pair.fee, // 0.05% fee
          poolLogicProxy.address,
          pair.amount0,
          minAmountOut,
          0,
        ],
      ]);

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
        iHasSupportedAsset.encodeFunctionData("isSupportedAsset", [pair.token1]),
        true,
      );

      await expect(
        deployments.uniswapV3RouterGuard
          .connect(anon)
          .txGuard(evilPoolManager.address, uniswapV3.router, exactInputSingleCalldata),
      ).to.be.revertedWith("not pool logic");

      await expect(
        deployments.uniswapV3RouterGuard
          .connect(anon)
          .txGuard(poolManagerLogicProxy.address, uniswapV3.router, exactInputSingleCalldata),
      ).to.be.revertedWith("not pool logic");

      expect(
        (await deployments.slippageAccumulator.managerData(poolManagerLogicProxy.address)).accumulatedSlippage,
      ).to.equal(constants.Zero, "Slippage impact detected");
    });
  });
};
