import { BigNumber } from "ethers";
import { assets } from "../../polygon-data";
import { getAccountTokens } from ".";

export const getUSDC = async (amount: BigNumber) => {
  await getAccountTokens(assets.usdc, amount, 0);
};
