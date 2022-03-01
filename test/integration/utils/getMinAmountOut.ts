import { ethers } from "hardhat";
import { BigNumber } from "ethers";

import { IDeployments } from "../utils/deployContracts";
import { units } from "../../TestHelpers";

/**
 * Gets a minimum amount out for swaps to pass Chainlink slippage checker
 * @param deployments
 * @param amountIn
 * @param tokenInAddress
 * @param tokenOutAddress
 * @returns
 */
export const getMinAmountOut = async (
  deployments: IDeployments,
  amountIn: BigNumber,
  tokenInAddress: string,
  tokenOutAddress: string,
  percentage: number = 91,
): Promise<BigNumber> => {
  const tokenIn = await ethers.getContractAt("IERC20Extended", tokenInAddress);
  const tokenOut = await ethers.getContractAt("IERC20Extended", tokenOutAddress);
  const tokenInPrice = await deployments.assetHandler.getUSDPrice(tokenIn.address);
  const tokenOutPrice = await deployments.assetHandler.getUSDPrice(tokenOut.address);

  const tokenInDecimals = await tokenIn.decimals();
  const tokenOutDecimals = await tokenOut.decimals();

  const exchangeRate = tokenInPrice.mul(units(1, tokenOutDecimals)).div(tokenOutPrice);
  const minAmountOut = amountIn.mul(exchangeRate).div(units(1, tokenInDecimals)).mul(percentage).div(100); // 91% minimum amount out

  return minAmountOut;
};
