import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { abi as uniswapV3FactoryAbi } from "@uniswap/v3-core/artifacts/contracts/UniswapV3Factory.sol/UniswapV3Factory.json";
import { abi as uniswapV3PoolAbi } from "@uniswap/v3-core/artifacts/contracts/UniswapV3Pool.sol/UniswapV3Pool.json";
import bn from "bignumber.js";
import type { Wallet } from "ethers";
import { BigNumber } from "ethers";
import { ethers } from "hardhat";
import { Address } from "../../../deployment-scripts/types";
import {
  IERC20__factory,
  INonfungiblePositionManager,
  INonfungiblePositionManager__factory,
  PoolFactory,
  PoolLogic,
} from "../../../types";
import { units } from "../../TestHelpers";
import { getAccountToken } from "./getAccountTokens";

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
  const token0Contract = await ethers.getContractAt("@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20", token0);
  await token0Contract.connect(user).approve(nonfungiblePositionManager.address, amount0);
  const token1Contract = await ethers.getContractAt("@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20", token1);
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
 * @param uniswapV3Factory Uniswap v3 Factory address
 * @param params Pool parameters
 * @returns Current rounded tick of pool
 */
export const getCurrentTick = async (
  uniswapV3Factory: Address,
  params: {
    token0: Address;
    token1: Address;
    fee: number;
  },
): Promise<number> => {
  const factory = await ethers.getContractAt(uniswapV3FactoryAbi, uniswapV3Factory);
  const poolAddress = await factory.getPool(params.token0, params.token1, params.fee);
  if (poolAddress === "0x0000000000000000000000000000000000000000") throw new Error("Invalid pool");
  const pool = await ethers.getContractAt(uniswapV3PoolAbi, poolAddress);
  const currentTick = parseInt((await pool.slot0()).tick);
  const tick = convertCurrentTick(currentTick, params.fee);
  return tick;
};

/**
 * Gets sqrtPriceX96 of Uniswap v3 pool
 * @param poolFactory dHEDGE Factory address
 * @param params Pool parameters
 * @returns
 */
export const getOracleSqrtPriceX96 = async (
  poolFactory: PoolFactory,
  params: {
    token0: Address;
    token1: Address;
  },
): Promise<BigNumber> => {
  const token0 = params.token0;
  const token1 = params.token1;
  const Token0 = await ethers.getContractAt("IERC20Extended", token0);
  const Token1 = await ethers.getContractAt("IERC20Extended", token1);

  const token0Price = await poolFactory.getAssetPrice(token0);
  const token1Price = await poolFactory.getAssetPrice(token1);
  const token0PriceNorm = token0Price
    .mul(BigNumber.from(10).pow(await Token1.decimals()))
    .div(BigNumber.from(10).pow(18));
  const token1PriceNorm = token1Price
    .mul(BigNumber.from(10).pow(await Token0.decimals()))
    .div(BigNumber.from(10).pow(18));

  const priceRatioX192 = token0PriceNorm.shl(192).div(token1PriceNorm);
  const oracleSqrtPriceX96 = sqrt(priceRatioX192);
  return oracleSqrtPriceX96;
};

function sqrt(value: BigNumber): BigNumber {
  return BigNumber.from(new bn(value.toString()).sqrt().toFixed(0));
}

/**
 * Gets sqrtPriceX96 of Uniswap v3 pool
 * @param uniswapV3Factory Uniswap v3 Factory address
 * @param params Pool parameters
 * @returns
 */
export const getCurrentSqrtPriceX96 = async (
  uniswapV3Factory: Address,
  params: {
    token0: Address;
    token1: Address;
    fee: number;
  },
): Promise<BigNumber> => {
  const token0 = params.token0;
  const token1 = params.token1;
  const fee = params.fee;
  const factory = await ethers.getContractAt(uniswapV3FactoryAbi, uniswapV3Factory);
  const poolAddress = await factory.getPool(token0, token1, fee);
  if (poolAddress === "0x0000000000000000000000000000000000000000") throw new Error("Invalid pool");
  const pool = await ethers.getContractAt(uniswapV3PoolAbi, poolAddress);
  const currentSqrtPriceX96 = (await pool.slot0()).sqrtPriceX96;
  return currentSqrtPriceX96;
};

//ethereum.stackexchange.com/questions/98685/computing-the-uniswap-v3-pair-price-from-q64-96-number
export const getCurrentPrice = async (
  uniswapV3Factory: Address,
  params: { token0: Address; token1: Address; fee: number },
): Promise<BigNumber> => {
  const { token0, token1, fee } = params;
  const factory = await ethers.getContractAt(uniswapV3FactoryAbi, uniswapV3Factory);
  const poolAddress = await factory.getPool(token0, token1, fee);
  if (poolAddress === "0x0000000000000000000000000000000000000000") throw new Error("Invalid pool");
  const pool = await ethers.getContractAt(uniswapV3PoolAbi, poolAddress);
  const sqrtPriceX96: BigNumber = (await pool.slot0()).sqrtPriceX96;
  return sqrtPriceX96
    .mul(sqrtPriceX96)
    .mul(units(1))
    .shr(96 * 2);
};

export const getSqrtPrice = async (
  uniswapV3Factory: Address,
  params: { token0: Address; token1: Address; fee: number },
): Promise<BigNumber> => {
  const { token0, token1, fee } = params;
  const factory = await ethers.getContractAt(uniswapV3FactoryAbi, uniswapV3Factory);
  const poolAddress = await factory.getPool(token0, token1, fee);
  if (poolAddress === "0x0000000000000000000000000000000000000000") throw new Error("Invalid pool");
  const pool = await ethers.getContractAt(uniswapV3PoolAbi, poolAddress);
  const sqrtPriceX96: BigNumber = (await pool.slot0()).sqrtPriceX96;
  return sqrtPriceX96;
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
 * @param params Pool parameters
 * @returns Current rounded tick of pool
 */
export const getV3LpBalances = async (
  uniswapV3Factory: Address,
  params: { token0: Address; token1: Address; fee: number },
): Promise<[BigNumber, BigNumber]> => {
  const factory = await ethers.getContractAt(uniswapV3FactoryAbi, uniswapV3Factory);
  const poolAddress = await factory.getPool(params.token0, params.token1, params.fee);
  const Token0 = await ethers.getContractAt("@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20", params.token0);
  const Token1 = await ethers.getContractAt("@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20", params.token1);

  return [await Token0.balanceOf(poolAddress), await Token1.balanceOf(poolAddress)];
};
