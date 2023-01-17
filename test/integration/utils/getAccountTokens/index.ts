import { BigNumber } from "ethers";
import { ethers, network } from "hardhat";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";

export const toBytes32 = (bn: BigNumber) => {
  return ethers.utils.hexlify(ethers.utils.zeroPad(bn.toHexString(), 32));
};

export const getAccountToken = async (
  amount: BigNumber,
  userAddress: string,
  tokenAddress: string,
  slot: number,
  retries = 0,
) => {
  try {
    // Get storage slot index
    const index = ethers.utils.solidityKeccak256(
      ["uint256", "uint256"],
      [userAddress, slot], // key, slot
    );

    if (amount.eq(0)) {
      await network.provider.request({
        method: "hardhat_impersonateAccount",
        params: [userAddress],
      });
      const user = await ethers.getSigner(userAddress);
      const token = await ethers.getContractAt("@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20", tokenAddress);
      if ((await token.balanceOf(user.address)).gt(0)) {
        await network.provider.send("hardhat_setBalance", [user.address, "0x100000000000000"]);
        await network.provider.send("evm_mine", []); // Just mines to the next block
        await token.connect(user).transfer((await ethers.getSigners())[0].address, await token.balanceOf(user.address));
      }
    } else {
      await network.provider.send("hardhat_setStorageAt", [tokenAddress, index, toBytes32(amount).toString()]);
      await network.provider.send("evm_mine", []); // Just mines to the next block
    }
  } catch (e) {
    // ProviderError: Errors encountered in param 1: Invalid value "0x00511642543ea57a6abb62be518cc6b3add24b15c7fd72c209a76de661a1b445" supplied to : QUANTITY
    console.error("Error at getAccountToken:", [amount, userAddress, tokenAddress, slot], e);
    if (retries < 3) {
      console.log("Retrying...");
      await getAccountToken(amount, userAddress, tokenAddress, slot, retries + 1);
    } else {
      throw e;
    }
  }
};

export const getAccountTokens = async (amount: BigNumber, tokenAddress: string, slot: number) => {
  const signers = await ethers.getSigners();
  for (const signer of signers) {
    await getAccountToken(amount, signer.address, tokenAddress, slot);
  }
};

export const approveToken = async (as: SignerWithAddress, address: string, token: string, amount: BigNumber) => {
  return (await ethers.getContractAt("@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20", token))
    .connect(as)
    .approve(address, amount);
};

export const getBalance = async (address: string, token: string): Promise<BigNumber> => {
  return (await ethers.getContractAt("@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20", token)).balanceOf(
    address,
  );
};
