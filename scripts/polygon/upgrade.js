const hre = require("hardhat");
const fs = require("fs");
const { getTag } = require("../Helpers");

let versions = require("../../publish/polygon/versions.json");
let tag = Object.keys(versions)[Object.keys(versions).length - 1];
let version = versions[tag].contracts;

async function main() {
  const ethers = hre.ethers;
  const artifacts = hre.artifacts;

  let network = await ethers.provider.getNetwork();
  console.log("network:", network);

  const signer = (await ethers.getSigners())[0];

  // should be changed with real manager and dao address
  const manager = (await ethers.getSigners())[0];
  const dao = (await ethers.getSigners())[0];

  console.log("signer address: ", signer.address);
  console.log("manager address: ", manager.address);
  console.log("dao address: ", dao.address);

  const IPoolLogic = await artifacts.readArtifact("PoolLogic");
  let poolLogic = await ethers.getContractAt(IPoolLogic.abi, version.PoolLogic);
  console.log("PoolLogic at", poolLogic.address);

  const IPoolManagerLogic = await artifacts.readArtifact("PoolManagerLogic");
  let poolManagerLogic = await ethers.getContractAt(IPoolManagerLogic.abi, version.PoolManagerLogic);
  console.log("PoolManagerLogic at", poolManagerLogic.address);

  const IPoolFactory = await artifacts.readArtifact("PoolFactory");
  const poolFactory = await ethers.getContractAt(IPoolFactory.abi, version.PoolFactoryProxy);
  console.log("PoolFactory at", poolFactory.address);

  const IAssetHandler = await artifacts.readArtifact("AssetHandler");
  const assetHandler = await ethers.getContractAt(IAssetHandler.abi, version.AssetHandlerProxy);
  console.log("AssetHandler at", assetHandler.address);

  const IERC20Guard = await artifacts.readArtifact("ERC20Guard");
  const erc20Guard = await ethers.getContractAt(IERC20Guard.abi, version.ERC20Guard);
  console.log("ERC20Guard at", erc20Guard.address);

  const IUniswapV2RouterGuard = await artifacts.readArtifact("UniswapV2RouterGuard");
  const uniswapV2RouterGuard = await ethers.getContractAt(IUniswapV2RouterGuard.abi, version.UniswapV2RouterGuard);
  console.log("UniswapV2RouterGuard at", uniswapV2RouterGuard.address);

  // redeploy pool logic and pool manager logic
  const PoolLogic = await ethers.getContractFactory("PoolLogic");
  poolLogic = await PoolLogic.deploy();
  await poolLogic.deployed();
  console.log("New PoolLogic deployed at ", poolLogic.address);

  const PoolManagerLogic = await ethers.getContractFactory("PoolManagerLogic");
  poolManagerLogic = await PoolManagerLogic.deploy();
  await poolManagerLogic.deployed();
  console.log("New PoolManagerLogic deployed at ", poolManagerLogic.address);

  // set new logics
  await poolFactory.setLogic(poolLogic.address, poolManagerLogic.address);

  versions[tag].date = new Date().toUTCString();
  versions[tag].contracts.PoolLogic = poolLogic.address;
  versions[tag].contracts.PoolManagerLogic = poolManagerLogic.address;

  // convert JSON object to string
  const data = JSON.stringify(versions, null, 2);
  console.log(data);

  fs.writeFileSync("publish/polygon/versions.json", data);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
