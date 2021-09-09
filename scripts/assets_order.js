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
    datas = [];
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
    datas.push(changeAssetsABI);
  }
  const upgradePoolBatchABI = PoolFactoryABI.encodeFunctionData("upgradePoolBatch(uint256, uint256, uint256, bytes[])", [0, deployedFunds.length - 1, "290", datas]);
  await proposeTx(poolFactoryProxy, upgradePoolBatchABI, "Pool Factory Batch Upgrade Pool");
};

main(NODE_ENV)
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
