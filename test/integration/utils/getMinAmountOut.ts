import { ethers } from "hardhat";
import { BigNumber } from "ethers";

import { units } from "../../testHelpers";
import { AssetHandler } from "../../../types";

/**
 * Gets a minimum amount out for swaps to pass Chainlink slippage checker
 * @param assetHandler
 * @param amountIn
 * @param tokenInAddress
 * @param tokenOutAddress
 * @returns
 */
export const getMinAmountOut = async (
  assetHandler: AssetHandler,
  amountIn: BigNumber,
  tokenInAddress: string,
  tokenOutAddress: string,
  percentage = 96,
): Promise<BigNumber> => {
  const tokenIn = await ethers.getContractAt("IERC20Extended", tokenInAddress);
  const tokenOut = await ethers.getContractAt("IERC20Extended", tokenOutAddress);
  const tokenInPrice = await assetHandler.getUSDPrice(tokenIn.address);
  const tokenOutPrice = await assetHandler.getUSDPrice(tokenOut.address);

  const tokenInDecimals = await tokenIn.decimals();
  const tokenOutDecimals = await tokenOut.decimals();

  const exchangeRate = tokenInPrice.mul(units(1, tokenOutDecimals)).div(tokenOutPrice);
  const minAmountOut = amountIn.mul(exchangeRate).div(units(1, tokenInDecimals)).mul(percentage).div(100); // 91% minimum amount out

  return minAmountOut;
};
