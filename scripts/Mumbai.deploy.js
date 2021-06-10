const hre = require('hardhat')
const fs = require('fs');
const { getTag } = require("./Helpers");

// Place holder addresses
const KOVAN_ADDRESS_RESOLVER = '0x823bE81bbF96BEc0e25CA13170F5AaCb5B79ba83';
const TESTNET_DAO = '0xab0c25f17e993F90CaAaec06514A2cc28DEC340b';

const sushiswapV2Router = "0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506";

// polygon mainnet
// const weth = "0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619";
// const usdc = "0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174";
// const usdt = "0xc2132D05D31c914a87C6611C10748AEb04B58e8F";
// const eth_price_feed = "0xF9680D99D6C9589e2a93a78A04A279e509205945";
// const usdc_price_feed = "0xfE4A8cc5b5B2366C1B58Bea3858e81843581b2F7";
// const usdt_price_feed = "0x0A6513e40db6EB1b165753AD52E80663aeA50545";

// polygon mumbai
// const dai = "0xcB1e72786A6eb3b44C2a2429e317c8a2462CFeb1";
// const weth = "0xA6FA4fB5f76172d178d61B04b0ecd319C5d1C0aa";
// const usdc = "0x2058A9D7613eEE744279e3856Ef0eAda5FCbaA7e";
// const usdt = "0x3813e82e6f7098b9583FC0F33a962D02018B6803";
const eth_price_feed = "0x0715A7794a1dc8e42615F059dD6e406A6594651A";
const matic_price_feed = "0xd0D5e3DB44DE05E9F294BB0a3bEEaF030DE24Ada";
const usdc_price_feed = "0x572dDec9087154dC5dfBB1546Bb62713147e0Ab0";
const usdt_price_feed = "0x92C09849638959196E976289418e5973CC96d645";
const dai_price_feed = "0x0FCAa9c899EC5A91eBc3D5Dd869De833b06fB046";

async function main () {
  const ethers = hre.ethers

  console.log('network:', await ethers.provider.getNetwork())

  const signer = (await ethers.getSigners())[0]

  // should be changed with real manager and dao address
  const manager = (await ethers.getSigners())[0]
  const dao = (await ethers.getSigners())[0]

  console.log('signer address: ', signer.address)
  console.log('manager address: ', manager.address)
  console.log('dao address: ', dao.address)

  const TestUSDT = await ethers.getContractFactory('TestUSDT');
  const tUSDT = await TestUSDT.deploy("1000000000");
  console.log("TestUSDT deployed at ", tUSDT.address);

  const TestUSDC = await ethers.getContractFactory('TestUSDC');
  const tUSDC = await TestUSDC.deploy("1000000000");
  console.log("TestUSDC deployed at ", tUSDC.address);

  const TestWETH = await ethers.getContractFactory('TestWETH');
  const tWETH = await TestWETH.deploy("1000000000");
  console.log("TestWETH deployed at ", tWETH.address);

  const AssetHandlerLogic = await ethers.getContractFactory('AssetHandler');
  const assetHandlerLogic = await AssetHandlerLogic.deploy();
  console.log("AssetHandler deployed at ", assetHandlerLogic.address);

  const PoolLogic = await ethers.getContractFactory("PoolLogic");
  const poolLogic = await PoolLogic.deploy();
  console.log("PoolLogic deployed at ", poolLogic.address);

  const PoolManagerLogic = await ethers.getContractFactory("PoolManagerLogic");
  const poolManagerLogic = await PoolManagerLogic.deploy();
  console.log("PoolManagerLogic deployed at ", poolManagerLogic.address)

  const PoolFactory = await ethers.getContractFactory("PoolFactory");
  let poolFactory = await PoolFactory.deploy();
  console.log("PoolFactory deployed at ", poolFactory.address);

  // Deploy ProxyAdmin
  const ProxyAdmin = await ethers.getContractFactory('ProxyAdmin');
  const proxyAdmin = await ProxyAdmin.deploy();
  await proxyAdmin.deployed();
  console.log("ProxyAdmin deployed at ", proxyAdmin.address);

  // Deploy AssetHandlerProxy
  const AssetHandlerProxy = await ethers.getContractFactory('OZProxy');
  const assetHandlerProxy = await AssetHandlerProxy.deploy(assetHandlerLogic.address, proxyAdmin.address, '0x');
  await assetHandlerProxy.deployed();
  console.log("AssetHandlerProxy deployed at ", assetHandlerProxy.address);

  const assetHandler = await AssetHandlerLogic.attach(assetHandlerProxy.address);

  // Deploy PoolFactoryProxy
  const PoolFactoryProxy = await ethers.getContractFactory('OZProxy');
  poolFactory = await PoolFactoryProxy.deploy(poolFactory.address, proxyAdmin.address, "0x");
  await poolFactory.deployed();
  console.log("PoolFactoryProxy deployed at ", poolFactory.address);

  // Initialize Asset Price Consumer
  const assetWeth = { asset: tWETH.address, assetType: 0, aggregator: eth_price_feed };
  const assetUsdt = { asset: tUSDT.address, assetType: 0, aggregator: usdt_price_feed };
  const assetUsdc = { asset: tUSDC.address, assetType: 0, aggregator: usdc_price_feed };
  const assetHandlerInitAssets = [assetWeth, assetUsdt, assetUsdc];

  await assetHandler.initialize(poolFactory.address, assetHandlerInitAssets);
  await assetHandler.deployed();
  console.log("AssetHandler initialized with TestUSDT, TestUSDC, TestWETH");

  poolFactory = await PoolFactory.attach(poolFactory.address);
  await poolFactory.initialize(poolLogic.address, poolManagerLogic.address, assetHandlerProxy.address, dao.address);
  await poolFactory.deployed();
  console.log("PoolFactoryProxy initialized");

  const ERC20Guard = await ethers.getContractFactory("ERC20Guard");
  const erc20Guard = await ERC20Guard.deploy();
  erc20Guard.deployed();
  console.log("ERC20Guard deployed at ", erc20Guard.address);

  const UniswapV2Guard = await ethers.getContractFactory("UniswapV2Guard");
  const uniswapV2Guard = await UniswapV2Guard.deploy();
  uniswapV2Guard.deployed();
  console.log("UniswapV2Guard deployed at ", uniswapV2Guard.address);

  await poolFactory.connect(dao).setAssetGuard(0, erc20Guard.address);
  await poolFactory.connect(dao).setContractGuard(sushiswapV2Router, uniswapV2Guard.address);
  console.log("PoolFactory set dao ", dao.address);

  let tag = await getTag();

  let versions = {
    "v2.0-alpha": {
      "tag": tag,
      "fulltag": "v2.0-alpha",
      "network": "mumbai",
      "date": new Date().toUTCString(),
      "contracts": {
        "TestUSDT": tUSDT.address,
        "TestUSDC": tUSDC.address,
        "TestWETH": tWETH.address,
        "USDT-Aggregator": usdt_price_feed,
        "USDC-Aggregator": usdc_price_feed,
        "ETH-Aggregator": eth_price_feed,
        "ProxyAdmin": proxyAdmin.address,
        "PoolFactoryProxy": poolFactory.address,
        "PoolLogic": poolLogic.address,
        "PoolManagerLogic": poolManagerLogic.address,
        "AssetHandlerProxy": assetHandlerProxy.address,
        "ERC20Guard": erc20Guard.address,
        "UniswapV2Guard": uniswapV2Guard.address,
      }
    }
  }

  // convert JSON object to string
  const data = JSON.stringify(versions, null, 2);
  console.log(data)

  fs.writeFileSync('publish/mumbai/versions.json', data);
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error)
    process.exit(1)
  })

