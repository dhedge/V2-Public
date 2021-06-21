const hre = require("hardhat");
const fs = require("fs");

let versions = require("../publish/mumbai/versions.json");
let tag = Object.keys(versions)[Object.keys(versions).length - 1];
let version = versions[tag].contracts;

const sushiswapV2Router = "0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506";
const sushiswapFactory = "0xc35DADB65012eC5796536bD9864eD8773aBc74C4";

const eth_price_feed = "0x0715A7794a1dc8e42615F059dD6e406A6594651A";
const matic_price_feed = "0xd0D5e3DB44DE05E9F294BB0a3bEEaF030DE24Ada";
const usdc_price_feed = "0x572dDec9087154dC5dfBB1546Bb62713147e0Ab0";
const usdt_price_feed = "0x92C09849638959196E976289418e5973CC96d645";
const dai_price_feed = "0x0FCAa9c899EC5A91eBc3D5Dd869De833b06fB046";
const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";

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

  const ITestUSDT = await artifacts.readArtifact("TestUSDT");
  const tUSDT = await ethers.getContractAt(ITestUSDT.abi, version.TestUSDT);
  console.log("TestUSDT at", tUSDT.address);

  const ITestUSDC = await artifacts.readArtifact("TestUSDC");
  const tUSDC = await ethers.getContractAt(ITestUSDC.abi, version.TestUSDC);
  console.log("TestUSDC at", tUSDC.address);

  const ITestWETH = await artifacts.readArtifact("TestWETH");
  const tWETH = await ethers.getContractAt(ITestWETH.abi, version.TestWETH);
  console.log("TestWETH at", tWETH.address);

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
  console.log("New PoolLogic deployed at ", poolLogic.address);

  const PoolManagerLogic = await ethers.getContractFactory("PoolManagerLogic");
  poolManagerLogic = await PoolManagerLogic.deploy();
  console.log("New PoolManagerLogic deployed at ", poolManagerLogic.address);

  // set new logics
  await poolFactory.setLogic(poolLogic.address, poolManagerLogic.address);

  versions[tag] = {
    tag: tag,
    network: network,
    date: new Date().toUTCString(),
    contracts: {
      TestUSDT: tUSDT.address,
      TestUSDC: tUSDC.address,
      TestWETH: tWETH.address,
      "USDT-Aggregator": usdt_price_feed,
      "USDC-Aggregator": usdc_price_feed,
      "ETH-Aggregator": eth_price_feed,
      PoolFactoryProxy: poolFactory.address,
      PoolLogic: poolLogic.address,
      PoolManagerLogic: poolManagerLogic.address,
      AssetHandlerProxy: assetHandler.address,
      ERC20Guard: erc20Guard.address,
      UniswapV2RouterGuard: uniswapV2RouterGuard.address,
    },
  };

  // convert JSON object to string
  const data = JSON.stringify(versions, null, 2);
  console.log(data);

  fs.writeFileSync("publish/mumbai/versions.json", data);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
