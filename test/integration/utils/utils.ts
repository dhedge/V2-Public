import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { config, ethers, network } from "hardhat";
import { HttpNetworkConfig } from "hardhat/types";
import { Func } from "mocha";
import { currentBlockTimestamp } from "../../testHelpers";
import { NETWORK } from "./deployContracts/deployContracts";

export type ChainIds = 137 | 10 | 42161 | 8453;

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

const impersonateAccounts = async (accounts: string[]) => {
  const signers: SignerWithAddress[] = [];

  for (let i = 0; i < accounts.length; ++i) {
    await network.provider.request({
      method: "hardhat_impersonateAccount",
      params: [accounts[i]],
    });

    await network.provider.send("hardhat_setBalance", [
      accounts[i],
      ethers.utils.hexValue(ethers.utils.parseEther("1000")),
    ]);

    signers[i] = await ethers.getSigner(accounts[i]);
  }

  return signers;
};

const impersonateAccount = async (account: string) => {
  return (await impersonateAccounts([account]))[0];
};

const increaseTime = async (seconds: number) => {
  await network.provider.send("evm_increaseTime", [seconds]);
  await network.provider.send("evm_mine");
};

const increaseBlocks = async (blocks: number) => {
  const blockNumberInHex = ethers.utils.hexValue(ethers.BigNumber.from(blocks));

  await network.provider.send("hardhat_mine", [blockNumberInHex.toString()]);
};

const evmForkNetwork = async (networkName: NETWORK, blockNumber?: number) => {
  await network.provider.request({
    method: "hardhat_reset",
    params: [
      {
        forking: {
          jsonRpcUrl: (config.networks[networkName] as HttpNetworkConfig).url,
          blockNumber,
        },
      },
    ],
  });
  await ethers.provider.send("evm_mine", []);
};

const evmForkReset = async () => {
  await network.provider.request({
    method: "hardhat_reset",
    params: [],
  });
  await ethers.provider.send("evm_mine", []);
};

const beforeAfterReset = (before: (fn: Func) => void, after: (fn: Func) => void) => {
  let snap: string;
  before(async () => {
    snap = await evmTakeSnap();
  });

  after(async () => {
    await evmRestoreSnap(snap, 3);
  });
};

const networkToChainIdMap: Record<NETWORK, ChainIds> = {
  polygon: 137,
  ovm: 10,
};

const delay = async (seconds = 4) => new Promise((_) => setTimeout(_, seconds * 1000));

const hashData = (dataTypes, dataValues) => {
  const bytes = ethers.utils.defaultAbiCoder.encode(dataTypes, dataValues);
  const hash = ethers.utils.keccak256(ethers.utils.arrayify(bytes));

  return hash;
};

const hashString = (string: string) => {
  return hashData(["string"], [string]);
};

const waitForRealTime = async () => {
  const currentBlock = await ethers.provider.getBlock("latest");
  const blockTimestamp = currentBlock.timestamp;

  console.log("Waiting for real-time to surpass blockchain time...");

  // Poll until the real time is greater than the blockchain timestamp
  while (Math.floor(Date.now() / 1000) <= blockTimestamp + 5) {
    await delay(1); // 1 second
  }
  console.log("Real-time has surpassed blockchain time.");
};

export const utils = {
  evmTakeSnap,
  evmRestoreSnap,
  increaseTime,
  increaseBlocks,
  impersonateAccounts,
  impersonateAccount,
  currentBlockTimestamp,
  evmForkNetwork,
  evmForkReset,
  beforeAfterReset,
  networkToChainIdMap,
  delay,
  hashData,
  hashString,
  waitForRealTime,
};
