import { proposeTx } from "../deploymentHelpers";
import dotenv from "dotenv";
import { IProposeTxProperties, IUpgradeConfigProposeTx } from "../types";
import { implementationStorageAddress } from "../common/deploymentData";

dotenv.config();
const NODE_ENV = process.env.NODE_ENV;

const main = async (NODE_ENV: string | undefined) => {
  // eslint-disable-next-line @typescript-eslint/no-var-requires
  const hre = require("hardhat");
  const { ethers } = hre;
  const network = await ethers.provider.getNetwork();
  console.log("network:", network);

  // Init tag
  const versionFile = NODE_ENV == "production" ? "versions" : "staging-versions";
  // eslint-disable-next-line @typescript-eslint/no-var-requires
  const versions = require(`../publish/${network.name}/${versionFile}.json`);
  const oldTag = Object.keys(versions)[Object.keys(versions).length - 1];
  console.log(`oldTag: ${oldTag}`);

  // Init contracts data
  const contracts = versions[oldTag].contracts;

  // Pool Factory
  const poolFactoryProxy = contracts.PoolFactoryProxy;
  const PoolFactory = await hre.artifacts.readArtifact("PoolFactory");
  const PoolFactoryABI = new ethers.utils.Interface(PoolFactory.abi);

  const pauseABI = PoolFactoryABI.encodeFunctionData("pause", []);
  const config: IUpgradeConfigProposeTx = {
    execute: false,
    restartnonce: false,
  };
  const addresses: IProposeTxProperties = {
    protocolDaoAddress: "",
    protocolTreasuryAddress: "",
    proxyAdminAddress: "",
    implementationStorageAddress,
  };
  await proposeTx(poolFactoryProxy, pauseABI, "Pause Pool Factory", config, addresses);

  // PoolManagerLogic PoolLogic
  const PoolFactoryContract = await ethers.getContractFactory("PoolFactory");
  const poolFactoryContract = await PoolFactoryContract.attach(poolFactoryProxy);
  const PoolLogic = await ethers.getContractFactory("PoolLogic");
  const PoolManagerLogic = await ethers.getContractFactory("PoolManagerLogic");
  let supportedAssets = [],
    poolLogic,
    poolManagerLogic;
  const datas = [],
    allSupportedAssets = [];

  // Governance
  const Governance = await hre.artifacts.readArtifact("Governance");
  const governanceABI = new ethers.utils.Interface(Governance.abi);

  // Set LendingEnabledAssetGuard assetType to 2
  const LendingEnabledAssetGuard = contracts.LendingEnabledAssetGuard;
  let setAssetGuardABI = governanceABI.encodeFunctionData("setAssetGuard", [2, LendingEnabledAssetGuard]);
  await proposeTx(
    contracts.Governance,
    setAssetGuardABI,
    "setAssetGuard for LendingEnabledAssetGuard",
    config,
    addresses,
  );

  // Set SushiLPAssetGuard assetType to 4
  const SushiLPAssetGuard = contracts.SushiLPAssetGuard;
  setAssetGuardABI = governanceABI.encodeFunctionData("setAssetGuard", [4, SushiLPAssetGuard]);
  await proposeTx(contracts.Governance, setAssetGuardABI, "setAssetGuard for SushiLPAssetGuard", config, addresses);

  const deployedFunds = await poolFactoryContract.getDeployedFunds();
  for (const fund of deployedFunds) {
    console.log("fund: ", fund);
    poolLogic = await PoolLogic.attach(fund);
    const poolManagerLogicAddress = await poolLogic.poolManagerLogic();
    poolManagerLogic = await PoolManagerLogic.attach(poolManagerLogicAddress);
    supportedAssets = await poolManagerLogic.getSupportedAssets();
    console.log("supportedAssets: ", supportedAssets);
    allSupportedAssets.push(supportedAssets);

    const PoolManagerLogicArtifact = await hre.artifacts.readArtifact("PoolManagerLogic");
    const PoolManagerLogicABI = new ethers.utils.Interface(PoolManagerLogicArtifact.abi);
    const changeAssetsABI = PoolManagerLogicABI.encodeFunctionData("changeAssets", [
      supportedAssets,
      supportedAssets.map((supportedAsset: never[]) => {
        return supportedAsset[0];
      }),
    ]);
    datas.push(changeAssetsABI);
  }
  console.log("allSupportedAssets: ", allSupportedAssets);
  console.log("datas: ", datas);

  for (let i = 0; i <= deployedFunds.length - 1; i += 50) {
    let params;
    if (i + 50 <= deployedFunds.length) {
      // Runds for 50 funds and slice is excluding last element
      params = [i, i + 49, "290", datas.slice(i, i + 50)];
    } else {
      // Runds for the rest funds funds and slice is excluding last element
      params = [i, deployedFunds.length - 1, "290", datas.slice(i, deployedFunds.length)];
    }
    const upgradePoolBatchABI = PoolFactoryABI.encodeFunctionData(
      "upgradePoolBatch(uint256, uint256, uint256, bytes[])",
      // [0, deployedFunds.length - 1, "290", datas], // Runs for all funds
      params,
    );
    await proposeTx(poolFactoryProxy, upgradePoolBatchABI, "Pool Factory Batch Upgrade Pool", config, addresses);
  }
};

main(NODE_ENV)
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
