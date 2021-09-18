const { proposeTx } = require("./Helpers");
require("dotenv").config();
const NODE_ENV = process.env.NODE_ENV;

const main = async (NODE_ENV) => {
  const network = await ethers.provider.getNetwork();
  console.log("network:", network);
  const hre = require("hardhat");

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
    poolManagerLogic,
    datas = [],
    allSupportedAssets = [];

  // Governance
  const Governance = await hre.artifacts.readArtifact("Governance");
  const governanceABI = new ethers.utils.Interface(Governance.abi);

  // Set LendingEnabledAssetGuard assetType to 2
  let LendingEnabledAssetGuard = contracts.LendingEnabledAssetGuard;
  let setAssetGuardABI = governanceABI.encodeFunctionData("setAssetGuard", [2, LendingEnabledAssetGuard]);
  await proposeTx(contracts.Governance, setAssetGuardABI, "setAssetGuard for LendingEnabledAssetGuard");

  // Set SushiLPAssetGuard assetType to 4
  let SushiLPAssetGuard = contracts.SushiLPAssetGuard;
  setAssetGuardABI = governanceABI.encodeFunctionData("setAssetGuard", [4, SushiLPAssetGuard]);
  await proposeTx(contracts.Governance, setAssetGuardABI, "setAssetGuard for SushiLPAssetGuard");

  const deployedFunds = await poolFactoryContract.getDeployedFunds();
  for (fund of deployedFunds) {
    console.log("fund: ", fund);
    poolLogic = await PoolLogic.attach(fund);
    poolManagerLogicAddress = await poolLogic.poolManagerLogic();
    poolManagerLogic = await PoolManagerLogic.attach(poolManagerLogicAddress);
    supportedAssets = await poolManagerLogic.getSupportedAssets();
    console.log("supportedAssets: ", supportedAssets);
    allSupportedAssets.push(supportedAssets);

    const PoolManagerLogicArtifact = await hre.artifacts.readArtifact("PoolManagerLogic");
    const PoolManagerLogicABI = new ethers.utils.Interface(PoolManagerLogicArtifact.abi);
    const changeAssetsABI = PoolManagerLogicABI.encodeFunctionData("changeAssets", [
      supportedAssets,
      supportedAssets.map((supportedAsset) => {
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
    await proposeTx(poolFactoryProxy, upgradePoolBatchABI, "Pool Factory Batch Upgrade Pool");
  }
};

main(NODE_ENV)
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
