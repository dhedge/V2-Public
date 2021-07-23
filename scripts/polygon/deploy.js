const hre = require("hardhat");
const fs = require("fs");
const { getTag } = require("../Helpers");
const csv = require("csvtojson");

// Place holder addresses
const KOVAN_ADDRESS_RESOLVER = "0x823bE81bbF96BEc0e25CA13170F5AaCb5B79ba83";
const TESTNET_DAO = "0xab0c25f17e993F90CaAaec06514A2cc28DEC340b";

const sushiswapV2Factory = "0xc35DADB65012eC5796536bD9864eD8773aBc74C4";
const sushiswapV2Router = "0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506";
const sushiMiniChefV2 = "0x0769fd68dFb93167989C6f7254cd0D766Fb2841F";

const wmatic = "0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270";
const weth = "0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619";
const usdc = "0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174";
const usdt = "0xc2132D05D31c914a87C6611C10748AEb04B58e8F";
const sushiToken = "0x0b3F868E0BE5597D5DB7fEB59E1CADBb0fdDa50a";

const matic_price_feed = "0xAB594600376Ec9fD91F8e885dADF0CE036862dE0";
const eth_price_feed = "0xF9680D99D6C9589e2a93a78A04A279e509205945";
const usdc_price_feed = "0xfE4A8cc5b5B2366C1B58Bea3858e81843581b2F7";
const usdt_price_feed = "0x0A6513e40db6EB1b165753AD52E80663aeA50545";
const sushi_price_feed = "0x49B0c695039243BBfEb8EcD054EB70061fd54aa0";

const sushiLpUsdcWeth = "0x34965ba0ac2451A34a0471F04CCa3F990b8dea27";
const sushiLPUsdcWethPoolId = 1;

const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";

async function main() {
  const ethers = hre.ethers;
  const upgrades = hre.upgrades;

  let network = await ethers.provider.getNetwork();
  console.log("network:", network);

  const signer = (await ethers.getSigners())[0];

  // should be changed with real manager and dao address
  const manager = (await ethers.getSigners())[0];
  const dao = (await ethers.getSigners())[0];

  console.log("signer address: ", signer.address);
  console.log("manager address: ", manager.address);
  console.log("dao address: ", dao.address);

  const Governance = await ethers.getContractFactory("Governance");
  let governance = await Governance.deploy();
  console.log("governance deployed to:", governance.address);

  const PoolLogic = await ethers.getContractFactory("PoolLogic");
  poolLogic = await PoolLogic.deploy();
  await poolLogic.deployed();
  console.log("poolLogic deployed at ", poolLogic.address);

  const PoolManagerLogic = await ethers.getContractFactory("PoolManagerLogic");
  poolManagerLogic = await PoolManagerLogic.deploy();
  await poolManagerLogic.deployed();
  console.log("poolManagerLogic deployed at ", poolManagerLogic.address);

  // Initialize Asset Price Consumer
  // const assetWmatic = { asset: wmatic, assetType: 0, aggregator: matic_price_feed };
  // const assetWeth = { asset: weth, assetType: 0, aggregator: eth_price_feed };
  // const assetUsdt = { asset: usdt, assetType: 0, aggregator: usdt_price_feed };
  // const assetUsdc = { asset: usdc, assetType: 0, aggregator: usdc_price_feed };
  // const assetSushi = { asset: sushiToken, assetType: 0, aggregator: sushi_price_feed };
  // const assetSushiLPWethUsdc = { asset: sushiLpUsdcWeth, assetType: 2, aggregator: sushiLPAggregatorUSDCWETH.address };
  // const assetHandlerInitAssets = [assetWmatic, assetWeth, assetUsdt, assetUsdc, assetSushi, assetSushiLPWethUsdc];

  const AssetHandlerLogic = await ethers.getContractFactory("AssetHandler");
  const assetHandler = await upgrades.deployProxy(AssetHandlerLogic, [[]]);
  await assetHandler.deployed();
  console.log("AssetHandler deployed at ", assetHandler.address);

  const PoolFactory = await ethers.getContractFactory("PoolFactory");
  poolFactory = await upgrades.deployProxy(PoolFactory, [
    poolLogic.address,
    poolManagerLogic.address,
    assetHandler.address,
    dao.address,
    governance.address,
  ]);
  await poolFactory.deployed();
  console.log("PoolFactoryProxy deployed at ", poolFactory.address);

  fileName = "./dHEDGE Assets list - Polygon.csv";

  const assets = await csv().fromFile(fileName);

  const SushiLPAggregator = await ethers.getContractFactory("SushiLPAggregator");
  let assetHandlerInitAssets = [];
  for (let i = 0; i < assets.length; i++) {
    const asset = assets[i];
    const assetType = asset.AssetType;
    switch (assetType) {
      case "2":
        // Deploy Sushi LP Aggregator
        console.log("Deploying ", asset["Asset Name"]);
        const sushiLPAggregator = await SushiLPAggregator.deploy(asset.Address, poolFactory.address);
        await sushiLPAggregator.deployed();
        console.log(`${asset["Asset Name"]} SushiLPAggregator deployed at `, sushiLPAggregator.address);
        assetHandlerInitAssets.push({
          name: asset["Asset Name"],
          asset: asset.Address,
          assetType: assetType,
          aggregator: sushiLPAggregator.address,
        });
        break;
      default:
        assetHandlerInitAssets.push({
          name: asset["Asset Name"],
          asset: asset.Address,
          assetType: assetType,
          aggregator: asset["Chainlink Price Feed"],
        });
    }
  }
  await assetHandler.addAssets(assetHandlerInitAssets);

  const ERC20Guard = await ethers.getContractFactory("ERC20Guard");
  const erc20Guard = await ERC20Guard.deploy();
  await erc20Guard.deployed();
  console.log("ERC20Guard deployed at ", erc20Guard.address);

  const UniswapV2RouterGuard = await ethers.getContractFactory("UniswapV2RouterGuard");
  const uniswapV2RouterGuard = await UniswapV2RouterGuard.deploy(sushiswapV2Factory);
  await uniswapV2RouterGuard.deployed();
  console.log("UniswapV2RouterGuard deployed at ", uniswapV2RouterGuard.address);

  const SushiMiniChefV2Guard = await ethers.getContractFactory("SushiMiniChefV2Guard");
  sushiMiniChefV2Guard = await SushiMiniChefV2Guard.deploy(sushiToken, wmatic);
  await sushiMiniChefV2Guard.deployed();
  console.log("SushiMiniChefV2Guard deployed at ", sushiMiniChefV2Guard.address);

  const SushiLPAssetGuard = await ethers.getContractFactory("SushiLPAssetGuard");
  sushiLPAssetGuard = await SushiLPAssetGuard.deploy(sushiMiniChefV2, [[sushiLpUsdcWeth, sushiLPUsdcWethPoolId]]); // initialise with Sushi staking pool Id
  await sushiLPAssetGuard.deployed();
  console.log("SushiLPAssetGuard deployed at ", sushiLPAssetGuard.address);

  await governance.setAssetGuard(0, erc20Guard.address);
  await governance.setAssetGuard(2, sushiLPAssetGuard.address);
  await governance.setContractGuard(sushiswapV2Router, uniswapV2RouterGuard.address);
  await governance.setContractGuard(sushiMiniChefV2, sushiMiniChefV2Guard.address);

  let tag = await getTag();
  let versions = require("../../publish/polygon/versions.json");
  versions[tag] = {
    network: network,
    date: new Date().toUTCString(),
    contracts: {
      Assets: assetHandlerInitAssets,
      Governance: governance.address,
      PoolFactoryProxy: poolFactory.address,
      PoolLogicProxy: poolLogic.address,
      PoolManagerLogicProxy: poolManagerLogic.address,
      AssetHandlerProxy: assetHandler.address,
      ERC20Guard: erc20Guard.address,
      UniswapV2RouterGuard: uniswapV2RouterGuard.address,
      SushiMiniChefV2Guard: sushiMiniChefV2Guard.address,
      SushiLPAssetGuard: sushiLPAssetGuard.address,
    },
  };

  // convert JSON object to string
  const data = JSON.stringify(versions, null, 2);
  console.log(data);

  fs.writeFileSync("./publish/polygon/versions.json", data);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
