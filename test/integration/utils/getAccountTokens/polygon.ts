import { BigNumber } from "ethers";
import { assets, assetsBalanceOfSlot } from "../../polygon-data";
import { getAccountToken, getAccountTokens } from ".";

export const getUSDC = async (amount: BigNumber, userAddress = "") => {
  if (!userAddress) {
    await getAccountTokens(amount, assets.usdc, assetsBalanceOfSlot.usdc);
  } else {
    await getAccountToken(amount, userAddress, assets.usdc, assetsBalanceOfSlot.usdc);
  }
};

export const getUSDT = async (amount: BigNumber, userAddress = "") => {
  if (!userAddress) {
    await getAccountTokens(amount, assets.usdt, assetsBalanceOfSlot.usdt);
  } else {
    await getAccountToken(amount, userAddress, assets.usdt, assetsBalanceOfSlot.usdt);
  }
};

export const getDAI = async (amount: BigNumber, userAddress = "") => {
  if (!userAddress) {
    await getAccountTokens(amount, assets.dai, assetsBalanceOfSlot.dai);
  } else {
    await getAccountToken(amount, userAddress, assets.dai, assetsBalanceOfSlot.dai);
  }
};

export const getWETH = async (amount: BigNumber, userAddress = "") => {
  if (userAddress) {
    await getAccountTokens(amount, assets.weth, assetsBalanceOfSlot.weth);
  } else {
    await getAccountToken(amount, userAddress, assets.weth, assetsBalanceOfSlot.weth);
  }
};
