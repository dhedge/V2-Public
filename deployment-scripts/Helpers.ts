import util from "util";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { exec } from "child_process";
import fs from "fs";
const execProm = util.promisify(exec);
import stringify from "csv-stringify/lib/sync";
import { SafeService } from "@gnosis.pm/safe-ethers-adapters";
import Safe, { EthersAdapter } from "@gnosis.pm/safe-core-sdk";
import { retryWithDelay } from "./utils";
import axios from "axios";
import { IProposeTxProperties, IUpgradeConfigProposeTx } from "./types";

let nonce: number;

export const nonceLog = new Array();

export const getTag = async () => {
  try {
    await execProm("git pull --tags");
  } catch {}
  let result = await execProm("git tag | sort -V | tail -1");
  return result.stdout.trim();
};

export const hasDuplicates = async (array: any, key: any) => {
  const valueArr = array.map(function (item: any) {
    return item[key];
  });

  const isDuplicate = valueArr.some(function (item: any, idx: number) {
    if (!item) return false;
    return valueArr.indexOf(item) != idx;
  });

  return isDuplicate;
};

export const isSameBytecode = (creationBytecode: string, runtimeBytecode: string) => {
  const bytecodeB = runtimeBytecode.substring(39);
  const bytecodeSnippet = bytecodeB.substring(0, 100);
  const indexOfSnippet = creationBytecode.indexOf(bytecodeSnippet);

  if (indexOfSnippet < 0) return false;
  const bytecodeA = creationBytecode.substring(indexOfSnippet);
  if (bytecodeA.length !== bytecodeB.length) return false;

  // Ignore the bytecode metadata https://docs.soliditylang.org/en/v0.7.6/metadata.html
  const metadataString = "a264"; // Note: this string might change in future compiler versions
  if (
    bytecodeA.substring(0, bytecodeA.indexOf(metadataString)) !==
    bytecodeB.substring(0, bytecodeB.indexOf(metadataString))
  )
    return false;

  return true;
};

export const tryVerify = async (
  hre: HardhatRuntimeEnvironment,
  address: string,
  path: string,
  constructorArguments: any[],
) => {
  await retryWithDelay(async () => {
    try {
      await hre.run("verify:verify", {
        address: address,
        contract: path,
        constructorArguments: constructorArguments,
      });
    } catch (e: any) {
      if (e.message.toLowerCase().includes("constructor arguments exceeds max accepted")) {
        // This error may be to do with the compiler, "constructor arguments exceeds max accepted (10k chars) length"
        // Possibly because the contract should have been compiled in isolation before deploying ie "compile:one"
        console.warn(`Couldn't verify contract at ${address}. Error: ${e.message}`);
        return;
      }
      if (!e.message.toLowerCase().includes("already verified")) {
        throw e;
      }
    }
  }, "Try Verify: " + address);
};

export const writeCsv = (data: any, fileName: string) => {
  const output = stringify(data, { header: true });
  fs.writeFileSync(fileName, output);
};

/// Converts a string into a hex representation of bytes32
export const toBytes32 = (key: string) => {
  const { ethers } = require("hardhat");
  return ethers.utils.formatBytes32String(key);
};

const getNonce = async (
  safeSdk: Safe,
  chainId: number,
  safeAddress: string,
  restartFromLastConfirmedNonce: boolean,
) => {
  const lastConfirmedNonce = await safeSdk.getNonce();
  if (restartFromLastConfirmedNonce) {
    console.log("GetNonce: Starting from LAST CONFIRMED NONCE: ", lastConfirmedNonce);
    return lastConfirmedNonce;
  }

  const safeTxApi = `https://safe-client.gnosis.io/v1/chains/${chainId}/safes/${safeAddress}/transactions/queued`;
  const response = await axios.get(safeTxApi);
  const results = response.data.results.reverse();
  const last = results.find((r: any) => r.type === "TRANSACTION");
  if (!last) {
    console.log("GetNonce: No Pending Nonce - Starting from LAST CONFIRMED NONCE: ", lastConfirmedNonce);
    return lastConfirmedNonce;
  }

  const nonce = last.transaction.executionInfo.nonce + 1;
  console.log("GetNonce: Starting from last PENDING nonce: ", nonce);
  return nonce;
};

export const proposeTx = async (
  to: string,
  data: string,
  message: string,
  config: IUpgradeConfigProposeTx,
  addresses: IProposeTxProperties,
) => {
  if (!config.execute) {
    console.log("Will propose transaction:", message);
    return;
  }

  // Initialize the Safe SDK
  const { ethers } = require("hardhat");
  const provider = ethers.provider;
  const owner1 = provider.getSigner(0);
  const ethAdapter = new EthersAdapter({ ethers: ethers, signer: owner1 });
  const chainId: number = await ethAdapter.getChainId();

  const service = new SafeService(addresses.gnosisApi);

  const contractNetworks: any = {
    [chainId]: {
      multiSendAddress: addresses.gnosisMultiSendAddress,
    },
  };

  let chainSafeAddress: string = addresses.protocolDaoAddress;

  const safeSdk = await Safe.create({
    ethAdapter,
    safeAddress: chainSafeAddress,
    contractNetworks,
  });

  nonce = nonce ? nonce : await getNonce(safeSdk, chainId, chainSafeAddress, config.restartnonce);

  const transaction = {
    to: to,
    value: "0",
    data: data,
    nonce: nonce,
  };

  const log = {
    nonce: nonce,
    message: message,
  };

  console.log("Proposing transaction: ", transaction);
  console.log(`Nonce Log`, log);
  nonceLog.push(log);

  nonce += 1;

  const safeTransaction = await safeSdk.createTransaction(...[transaction]);
  // off-chain sign
  const txHash = await safeSdk.getTransactionHash(safeTransaction);
  const signature = await safeSdk.signTransactionHash(txHash);
  // on-chain sign
  // const approveTxResponse = await safeSdk.approveTransactionHash(txHash)
  // console.log("approveTxResponse", approveTxResponse);
  console.log("safeTransaction: ", safeTransaction);

  await retryWithDelay(
    async () => await service.proposeTx(chainSafeAddress, txHash, safeTransaction, signature),
    "Gnosis safe",
  );
};

export const checkAsset = async (csvAsset: any, contracts: any, poolFactory: any, assetHandlerAssets: any) => {
  for (const asset of contracts.Assets) {
    // if (csvAsset["AssetName"] === "Sushi") sushiToken = csvAsset.Address;
    // if (csvAsset["AssetName"] === "Wrapped Matic") wmatic = csvAsset.Address;
    if (csvAsset["Address"].toLowerCase() === asset.asset.toLowerCase()) {
      // console.log(`csvAsset: ${csvAsset["AssetName"]} is already in the current contracts.Assets`);
      const assetType = parseInt(await poolFactory.getAssetType(csvAsset.Address));

      if (assetType !== parseInt(csvAsset.AssetType)) {
        console.log(`${csvAsset["AssetName"]} asset type update from ${assetType} to ${csvAsset.AssetType}`);
        assetHandlerAssets.push({
          name: csvAsset["AssetName"],
          asset: csvAsset.Address,
          assetType: csvAsset.AssetType,
          aggregator: csvAsset["ChainlinkPriceFeed"],
        });
      }

      const foundInVersions = true;
      return foundInVersions;
    }
  }
  const foundInVersions = false;
  return foundInVersions;
};

export const checkBalancerLpAsset = async (
  balancerLp: any,
  contracts: any,
  poolFactory: any,
  assetHandlerAssets: any,
) => {
  for (const asset of contracts.Assets) {
    if (balancerLp.name === asset.name) {
      // console.log(`${balancerLp.name} is already in the current contracts.Assets`);
      const assetType = parseInt(await poolFactory.getAssetType(balancerLp.address));

      if (assetType !== balancerLp.assetType) {
        console.log(`${balancerLp.name} asset type update from ${assetType} to ${balancerLp.assetType}`);
        assetHandlerAssets.push({
          name: balancerLp.name,
          asset: balancerLp.data.pool,
          assetType: balancerLp.assetType,
          aggregator: asset.aggregator,
        });
      }

      const foundInVersions = true;
      return foundInVersions;
    }
  }
  const foundInVersions = false;
  return foundInVersions;
};

export const getAggregator = async (hre: HardhatRuntimeEnvironment, csvAsset: any) => {
  const AggregatorName = csvAsset["AggregatorName"];

  switch (AggregatorName) {
    case "DHedgePoolAggregator":
      // Deploy DHedgePoolAggregator
      const assetAddress = csvAsset["Address"];
      const { ethers } = hre;
      const DHedgePoolAggregator = await ethers.getContractFactory("DHedgePoolAggregator");
      const dHedgePoolAggregator = await DHedgePoolAggregator.deploy(assetAddress);
      await dHedgePoolAggregator.deployed();
      await tryVerify(
        hre,
        dHedgePoolAggregator.address,
        "contracts/priceAggregators/DHedgePoolAggregator.sol:DHedgePoolAggregator",
        [assetAddress],
      );
      return dHedgePoolAggregator.address;
    case "USDPriceAggregator":
      // Deploy USDPriceAggregator
      const USDPriceAggregator = await ethers.getContractFactory("USDPriceAggregator");
      const usdPriceAggregator = await USDPriceAggregator.deploy();
      await usdPriceAggregator.deployed();
      return usdPriceAggregator.address;
    default:
      return csvAsset["ChainlinkPriceFeed"];
  }
};
