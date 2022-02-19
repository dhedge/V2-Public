import { ethers, network } from "hardhat";

const evmTakeSnap = async (): Promise<string> => {
  const x = (await network.provider.request({
    method: "evm_snapshot",
    params: [],
  })) as string;
  await ethers.provider.send("evm_mine", []); // Just mines to the next block
  return x;
};

const evmRestoreSnap = async (id: string, retries = 0) => {
  try {
    await network.provider.request({
      method: "evm_revert",
      params: [id],
    });
    await ethers.provider.send("evm_mine", []); // Just mines to the next block
  } catch (e) {
    console.error("Error when reverting", id, e);
    if (retries < 3) {
      console.log("Retrying to revert to", id);
      evmRestoreSnap(id, retries++);
    }
  }
};

export const utils = {
  evmTakeSnap,
  evmRestoreSnap,
};
