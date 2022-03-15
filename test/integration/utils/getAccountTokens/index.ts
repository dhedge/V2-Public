import { BigNumber } from "ethers";
import { ethers } from "hardhat";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";

export const toBytes32 = (bn: BigNumber) => {
  return ethers.utils.hexlify(ethers.utils.zeroPad(bn.toHexString(), 32));
};

export const getAccountToken = async (amount: BigNumber, userAddress: string, tokenAddress: string, slot: number) => {
  // Get storage slot index
  const index = ethers.utils.solidityKeccak256(
    ["uint256", "uint256"],
    [userAddress, slot], // key, slot
  );

  await ethers.provider.send("hardhat_setStorageAt", [tokenAddress, index, toBytes32(amount).toString()]);
  await ethers.provider.send("evm_mine", []); // Just mines to the next block
};

export const getAccountTokens = async (amount: BigNumber, tokenAddress: string, slot: number) => {
  const signers = await ethers.getSigners();
  for (const signer of signers) {
    await getAccountToken(amount, signer.address, tokenAddress, slot);
  }
};

export const approveToken = async (as: SignerWithAddress, address: string, token: string, amount: BigNumber) => {
  return (await ethers.getContractAt("IERC20", token)).connect(as).approve(address, amount);
};

export const getBalance = async (address: string, token: string) => {
  return (await ethers.getContractAt("IERC20", token)).balanceOf(address);
};
