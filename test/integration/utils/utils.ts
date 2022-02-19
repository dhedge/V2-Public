import { ethers, network } from "hardhat";

const evmTakeSnap = async (): Promise<string> => {
  const x = (await network.provider.request({
    method: "evm_snapshot",
    params: [],
  })) as string;
  // This seems to prevent the old
  // ProviderError: Errors encountered in param 1: Invalid value "0x02e5dda5c51be531e95b2e5b22389b23cd39a929c1a594052162ebe432d897e9" supplied to : QUANTITY
  await ethers.provider.send("evm_mine", []); // Just mines to the next block
  return x;
};

const evmRestoreSnap = async (id: string, retries = 0) => {
  try {
    await network.provider.request({
      method: "evm_revert",
      params: [id],
    });
    // This seems to prevent the old
    // ProviderError: Errors encountered in param 1: Invalid value "0x02e5dda5c51be531e95b2e5b22389b23cd39a929c1a594052162ebe432d897e9" supplied to : QUANTITY
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
