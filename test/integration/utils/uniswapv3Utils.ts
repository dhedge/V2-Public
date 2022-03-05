import { ethers } from "hardhat";
import { abi as uniswapV3FactoryAbi } from "@uniswap/v3-core/artifacts/contracts/UniswapV3Factory.sol/UniswapV3Factory.json";
import { abi as uniswapV3PoolAbi } from "@uniswap/v3-core/artifacts/contracts/UniswapV3Pool.sol/UniswapV3Pool.json";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { BigNumber } from "ethers";
import type { Wallet } from "ethers";

import {
  IERC20__factory,
  INonfungiblePositionManager,
  INonfungiblePositionManager__factory,
  PoolLogic,
} from "../../../types";
import { getAccountToken } from "./getAccountTokens";
import { Address } from "../../../deployment-scripts/types";
import { IUniswapV3Pool__factory } from "../../../types/factories/IUniswapV3Pool__factory";

const iERC20 = new ethers.utils.Interface(IERC20__factory.abi);
const iNonfungiblePositionManager = new ethers.utils.Interface(INonfungiblePositionManager__factory.abi);
const deadLine = Math.floor(Date.now() / 1000 + 100000000);
export interface UniV3LpMintSettings {
  token0: Address;
  token1: Address;
  fee: number;
  amount0: BigNumber;
  amount1: BigNumber;
  tickLower: number;
  tickUpper: number;
}

export const mintLpAsUser = async (
  nonfungiblePositionManager: INonfungiblePositionManager,
  user: Wallet | SignerWithAddress,
  mintSettings: UniV3LpMintSettings,
  assetSlots = [0, 0],
) => {
  const token0 = mintSettings.token0;
  const token1 = mintSettings.token1;
  const fee = mintSettings.fee;
  const amount0 = mintSettings.amount0;
  const amount1 = mintSettings.amount1;
  const tickLower = mintSettings.tickLower;
  const tickUpper = mintSettings.tickUpper;

  await getAccountToken(amount0, user.address, token0, assetSlots[0]);
  await getAccountToken(amount1, user.address, token1, assetSlots[1]);
  // Approve nft manager to take tokens
  const token0Contract = await ethers.getContractAt("IERC20", token0);
  await token0Contract.connect(user).approve(nonfungiblePositionManager.address, amount0);
  const token1Contract = await ethers.getContractAt("IERC20", token1);
  await token1Contract.connect(user).approve(nonfungiblePositionManager.address, amount1);

  await nonfungiblePositionManager.connect(user).mint({
    token0,
    token1,
    fee,
    tickLower,
    tickUpper,
    amount0Desired: amount0,
    amount1Desired: amount1,
    amount0Min: 0,
    amount1Min: 0,
    recipient: user.address,
    deadline: deadLine,
  });
};

/**
 * Mints Uni v3 LP for the pool from the manager
 * @param poolLogicProxy poolLogicProxy contract
 * @param manager Manager address
 * @param mintSettings LP configuration
 * @param approveTokens Approval of underlying tokens for transfer
 */
export const mintLpAsPool = async (
  nonfungiblePositionManager: Address,
  poolLogicProxy: PoolLogic,
  manager: SignerWithAddress,
  mintSettings: UniV3LpMintSettings,
  approveTokens = false,
) => {
  const token0 = mintSettings.token0;
  const token1 = mintSettings.token1;
  const fee = mintSettings.fee;
  const amount0 = mintSettings.amount0;
  const amount1 = mintSettings.amount1;
  const tickLower = mintSettings.tickLower;
  const tickUpper = mintSettings.tickUpper;

  if (approveTokens) {
    const approve0ABI = iERC20.encodeFunctionData("approve", [nonfungiblePositionManager, amount0]);
    await poolLogicProxy.connect(manager).execTransaction(token0, approve0ABI);
    const approve1ABI = iERC20.encodeFunctionData("approve", [nonfungiblePositionManager, amount1]);
    await poolLogicProxy.connect(manager).execTransaction(token1, approve1ABI);
  }

  const mintABI = iNonfungiblePositionManager.encodeFunctionData("mint", [
    [token0, token1, fee, tickLower, tickUpper, amount0, amount1, 0, 0, poolLogicProxy.address, deadLine],
  ]);

  await poolLogicProxy.connect(manager).execTransaction(nonfungiblePositionManager, mintABI);
};

/**
 * Gets tick of Uniswap v3 pool
 * @param token0 Token0 of pool
 * @param token1 Token1 of pool
 * @param fee Fee of pool
 * @returns Current rounded tick of pool
 */
export const getCurrentTick = async (
  uniswapV3Factory: Address,
  token0: Address,
  token1: Address,
  fee: number,
): Promise<number> => {
  const factory = await ethers.getContractAt(uniswapV3FactoryAbi, uniswapV3Factory);
  const poolAddress = await factory.getPool(token0, token1, fee);
  if (poolAddress === "0x0000000000000000000000000000000000000000") throw new Error("Invalid pool");
  const pool = await ethers.getContractAt(uniswapV3PoolAbi, poolAddress);
  const currentTick = parseInt((await pool.slot0()).tick);
  const tick = convertCurrentTick(currentTick, fee);
  return tick;
};

/**
 * Converts current pool tick to be rounded to nearest tick edge
 * @param currentTick Current tick of pool
 * @param fee Fee of the pool
 * @returns Rounded tick
 */
const convertCurrentTick = (currentTick: number, fee: number): number => {
  const tickMod = currentTick % (fee / 50);
  return currentTick - tickMod;
};

/**
 * Gets tick of Uniswap v3 pool
 * @param token0 Token0 of pool
 * @param token1 Token1 of pool
 * @param fee Fee of pool
 * @returns Current rounded tick of pool
 */
export const getV3LpBalances = async (
  uniswapV3Factory: Address,
  token0: Address,
  token1: Address,
  fee: number,
): Promise<[BigNumber, BigNumber]> => {
  const factory = await ethers.getContractAt(uniswapV3FactoryAbi, uniswapV3Factory);
  const poolAddress = await factory.getPool(token0, token1, fee);
  const Token0 = await ethers.getContractAt("IERC20", token0);
  const Token1 = await ethers.getContractAt("IERC20", token1);

  return [await Token0.balanceOf(poolAddress), await Token1.balanceOf(poolAddress)];
};
