const Safe = require("@gnosis.pm/safe-core-sdk");
const { EthersAdapter } = require("@gnosis.pm/safe-core-sdk");
const { SafeService } = require("@gnosis.pm/safe-ethers-adapters");
const proxyAdminAddress = "0x0C0a10C9785a73018077dBC74B2A006695849252";
const safeAddress = "0xc715Aa67866A2FEF297B12Cb26E953481AeD2df4";
// https://github.com/gnosis/safe-deployments/blob/main/src/assets/v1.3.0/multi_send.json#L13
const multiSendAddress = "0xA238CBeb142c10Ef7Ad8442C6D1f9E89e07e7761";
const service = new SafeService("https://safe-transaction.polygon.gnosis.io");
require("dotenv").config();
const NODE_ENV = process.env.NODE_ENV;

let nonce,
  safeSdk,
  nonceLog = new Array();

const proposeTx = async (to, data, message) => {
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

const main = async (NODE_ENV) => {
  // Initialize the Safe SDK
  const provider = ethers.provider;
  const owner1 = provider.getSigner(0);
  const ethAdapter = new EthersAdapter({ ethers: ethers, signer: owner1 });
  const chainId = await ethAdapter.getChainId();
  const hre = require("hardhat");
  const contractNetworks = {
    [chainId]: {
      multiSendAddress: multiSendAddress,
    },
  };

  safeSdk = await Safe.default.create({
    ethAdapter,
    safeAddress: safeAddress,
    contractNetworks,
  });
  nonce = await safeSdk.getNonce();
  const owner1Address = await owner1.getAddress();

  const network = await ethers.provider.getNetwork();
  console.log("network:", network);

  // Init tag
  const versionFile = NODE_ENV == "production" ? "versions" : "staging-versions";
  const versions = require(`../publish/${network.name}/${versionFile}.json`);
  const oldTag = Object.keys(versions)[Object.keys(versions).length - 1];
  console.log(`oldTag: ${oldTag}`);

  // Init contracts data
  const contracts = versions[oldTag].contracts;

  // Pool Factory
  let poolFactoryProxy = contracts.PoolFactoryProxy;
  const PoolFactory = await hre.artifacts.readArtifact("PoolFactory");
  const PoolFactoryABI = new ethers.utils.Interface(PoolFactory.abi);

  const pauseABI = PoolFactoryABI.encodeFunctionData("pause", []);
  await proposeTx(poolFactoryProxy, pauseABI, "Pause Pool Factory");

  // PoolManagerLogic PoolLogic
  const PoolFactoryContract = await ethers.getContractFactory("PoolFactory");
  const poolFactoryContract = await PoolFactoryContract.attach(poolFactoryProxy);
  const PoolLogic = await ethers.getContractFactory("PoolLogic");
  const PoolManagerLogic = await ethers.getContractFactory("PoolManagerLogic");
  let supportedAssets = [],
    poolLogic,
    poolManagerLogic;
  const deployedFunds = await poolFactoryContract.getDeployedFunds();
  for (fund of deployedFunds) {
    console.log("fund: ", fund);
    poolLogic = await PoolLogic.attach(fund);
    poolManagerLogicAddress = await poolLogic.poolManagerLogic();
    poolManagerLogic = await PoolManagerLogic.attach(poolManagerLogicAddress);
    supportedAssets = await poolManagerLogic.getSupportedAssets();
    console.log("supportedAssets: ", supportedAssets);

    const PoolManagerLogicArtifact = await hre.artifacts.readArtifact("PoolManagerLogic");
    const PoolManagerLogicABI = new ethers.utils.Interface(PoolManagerLogicArtifact.abi);
    const changeAssetsABI = PoolManagerLogicABI.encodeFunctionData("changeAssets", [
      supportedAssets,
      supportedAssets.map((supportedAsset) => {
        return supportedAsset[0];
      }),
    ]);
    const upgradePoolABI = PoolFactoryABI.encodeFunctionData("upgradePool", [fund, changeAssetsABI, "290"]);
    await proposeTx(poolFactoryProxy, upgradePoolABI, "Pool Factory Upgrade Pool");
  }
};

main(NODE_ENV)
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
