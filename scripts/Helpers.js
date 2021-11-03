const util = require("util");
const { exec } = require("child_process");
const execProm = util.promisify(exec);
const stringify = require("csv-stringify/lib/sync");
const fs = require("fs");
const Safe = require("@gnosis.pm/safe-core-sdk");
const { EthersAdapter } = require("@gnosis.pm/safe-core-sdk");
const { SafeService } = require("@gnosis.pm/safe-ethers-adapters");
const safeAddress = "0xc715Aa67866A2FEF297B12Cb26E953481AeD2df4";
// https://github.com/gnosis/safe-deployments/blob/main/src/assets/v1.3.0/multi_send.json#L13
const multiSendAddress = "0xA238CBeb142c10Ef7Ad8442C6D1f9E89e07e7761";
const service = new SafeService("https://safe-transaction.polygon.gnosis.io");
let nonce,
  safeSdk,
  chainId,
  nonceLog = new Array();

const getTag = async () => {
  try {
    await execProm("git pull --tags");
  } catch {}
  let result = await execProm("git tag | sort -V | tail -1");
  return result.stdout.trim();
};

const hasDuplicates = async (array, key) => {
  const valueArr = array.map(function (item) {
    return item[key];
  });

  const isDuplicate = valueArr.some(function (item, idx) {
    if (!item) return false;
    return valueArr.indexOf(item) != idx;
  });

  return isDuplicate;
};

const isSameBytecode = (creationBytecode, runtimeBytecode) => {
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

const tryVerify = async (hre, address, path, constructorArguments) => {
  try {
    await hre.run("verify:verify", {
      address: address,
      contract: path,
      constructorArguments: constructorArguments,
    });
  } catch (err) {
    console.log("Error: ", err);
  }
};

const writeCsv = (data, fileName) => {
  const output = stringify(data, { header: true });
  fs.writeFileSync(fileName, output, (err) => {
    if (err) {
      console.log(err);
    }
    console.log(`${fileName} updated.`);
  });
};

/// Converts a string into a hex representation of bytes32
const toBytes32 = (key) => ethers.utils.formatBytes32String(key);

const proposeTx = async (to, data, message, execute = false) => {
  if (!execute) {
    console.log("Will propose transaction:", message);
    return;
  }

  // Initialize the Safe SDK
  const provider = ethers.provider;
  const owner1 = provider.getSigner(0);
  const ethAdapter = new EthersAdapter({ ethers: ethers, signer: owner1 });
  chainId = chainId ? chainId : await ethAdapter.getChainId();

  const contractNetworks = {
    [chainId]: {
      multiSendAddress: multiSendAddress,
    },
  };

  safeSdk = safeSdk
    ? safeSdk
    : await Safe.default.create({
        ethAdapter,
        safeAddress: safeAddress,
        contractNetworks,
      });
  nonce = nonce ? nonce : await safeSdk.getNonce();

  const transaction = {
    to: to,
    value: "0",
    data: data,
    nonce: nonce,
  };

  nonceLog.push({
    nonce: nonce,
    message: message,
  });

  console.log("Proposing transaction: ", transaction);
  console.log(`Nonce ${nonce}: ${message}`);

  nonce += 1;

  const safeTransaction = await safeSdk.createTransaction(...[transaction]);
  // off-chain sign
  const txHash = await safeSdk.getTransactionHash(safeTransaction);
  const signature = await safeSdk.signTransactionHash(txHash);
  // on-chain sign
  // const approveTxResponse = await safeSdk.approveTransactionHash(txHash)
  // console.log("approveTxResponse", approveTxResponse);
  console.log("safeTransaction: ", safeTransaction);

  const proposeTx = await service.proposeTx(safeAddress, txHash, safeTransaction, signature);
  console.log("ProposeTx: ", proposeTx);
};

const checkAsset = async (csvAsset, contracts, poolFactory, assetHandlerAssets) => {
  for (const asset of contracts.Assets) {
    if (csvAsset["Asset Name"] === "Sushi") sushiToken = csvAsset.Address;
    if (csvAsset["Asset Name"] === "Wrapped Matic") wmatic = csvAsset.Address;
    if (csvAsset["Asset Name"] === asset.name) {
      // console.log(`csvAsset: ${csvAsset["Asset Name"]} is already in the current contracts.Assets`);
      const assetType = parseInt(await poolFactory.getAssetType(csvAsset.Address));

      if (assetType !== parseInt(csvAsset.AssetType)) {
        console.log(`${csvAsset["Asset Name"]} asset type update from ${assetType} to ${csvAsset.AssetType}`);
        assetHandlerAssets.push({
          name: csvAsset["Asset Name"],
          asset: csvAsset.Address,
          assetType: csvAsset.AssetType,
          aggregator: csvAsset["Chainlink Price Feed"],
        });
      }

      const foundInVersions = true;
      return foundInVersions;
    }
  }
  const foundInVersions = false;
  return foundInVersions;
};

const checkBalancerLpAsset = async (balancerLp, contracts, poolFactory, assetHandlerAssets) => {
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

const getAggregator = async (csvAsset) => {
  const assetName = csvAsset["aggregatorName"];
  let aggregator;

  switch (assetName) {
    case "DHedgePoolAggregator":
      // Deploy DHedgePoolAggregator
      const assetAddress = csvAsset["Address"];
      const DHedgePoolAggregator = await ethers.getContractFactory("DHedgePoolAggregator");
      const dHedgePoolAggregator = await DHedgePoolAggregator.deploy(assetAddress);
      await dHedgePoolAggregator.deployed();
      await tryVerify(
        hre,
        dHedgePoolAggregator.address,
        "contracts/assets/DHedgePoolAggregator.sol:DHedgePoolAggregator",
        [assetAddress],
      );
      aggregator = dHedgePoolAggregator.address;
      break;
    default:
      aggregator = csvAsset["Chainlink Price Feed"];
  }

  return aggregator;
};

module.exports = {
  writeCsv,
  tryVerify,
  getTag,
  hasDuplicates,
  isSameBytecode,
  toBytes32,
  proposeTx,
  nonceLog,
  checkAsset,
  checkBalancerLpAsset,
  getAggregator,
};
