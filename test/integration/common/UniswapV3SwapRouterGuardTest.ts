import { ethers } from "hardhat";
import { expect } from "chai";
import { checkAlmostSame } from "../../TestHelpers";
import {
  IERC20__factory,
  IMulticallExtended__factory,
  IV3SwapRouter__factory,
  PoolFactory,
  PoolLogic,
  PoolManagerLogic,
} from "../../../types";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { createFund } from "../utils/createFund";
import { getAccountToken } from "../utils/getAccountTokens";
import { BigNumber } from "ethers";
import { deployContracts, IDeployments, NETWORK } from "../utils/deployContracts/deployContracts";
import { getMinAmountOut } from "../utils/getMinAmountOut";
import { utils } from "../utils/utils";

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
}

export const uniswapV3SwapRouterGuardTest = (params: IUniswapV3SwapRouterGuardTestParameter) => {
  const { network, uniswapV3, pair } = params;

  describe("Uniswap V3 Swap Router Test", function () {
    let deployments: IDeployments;
    let logicOwner: SignerWithAddress, manager: SignerWithAddress;
    let poolFactory: PoolFactory, poolLogicProxy: PoolLogic, poolManagerLogicProxy: PoolManagerLogic;
    const iERC20 = new ethers.utils.Interface(IERC20__factory.abi);
    const IV3SwapRouter = new ethers.utils.Interface(IV3SwapRouter__factory.abi);
    const iMulticall = new ethers.utils.Interface(IMulticallExtended__factory.abi);

    before(async function () {
      [logicOwner, manager] = await ethers.getSigners();

      deployments = await deployContracts(network);
      poolFactory = deployments.poolFactory;
    });

    let snapId: string;
    afterEach(async () => {
      await utils.evmRestoreSnap(snapId);
    });
    beforeEach(async () => {
      snapId = await utils.evmTakeSnap();

      const funds = await createFund(poolFactory, logicOwner, manager, [
        { asset: pair.token0, isDeposit: true },
        { asset: pair.token1, isDeposit: true },
      ]);
      poolLogicProxy = funds.poolLogicProxy;
      poolManagerLogicProxy = funds.poolManagerLogicProxy;

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
  });
};
