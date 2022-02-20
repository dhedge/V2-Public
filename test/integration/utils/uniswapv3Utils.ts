import { ethers } from "hardhat";
import { abi as uniswapV3FactoryAbi } from "@uniswap/v3-core/artifacts/contracts/UniswapV3Factory.sol/UniswapV3Factory.json";
import { abi as uniswapV3PoolAbi } from "@uniswap/v3-core/artifacts/contracts/UniswapV3Pool.sol/UniswapV3Pool.json";

import { Address } from "../../../deployment-scripts/types";
import { uniswapV3 } from "../../../config/chainData/polygon-data";

/**
 * Gets tick of Uniswap v3 pool
 * @param token0 Token0 of pool
 * @param token1 Token1 of pool
 * @param fee Fee of pool
 * @returns Current rounded tick of pool
 */
export const getCurrentTick = async (token0: Address, token1: Address, fee: number): Promise<number> => {
  const factory = await ethers.getContractAt(uniswapV3FactoryAbi, uniswapV3.factory);
  const poolAddress = await factory.getPool(token0, token1, fee);
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
export const convertCurrentTick = (currentTick: number, fee: number): number => {
  const tickMod = currentTick % (fee / 50);
  return currentTick - tickMod;
};
