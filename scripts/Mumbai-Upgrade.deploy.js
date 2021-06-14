const hre = require('hardhat')
const fs = require('fs');
const versions = require("../publish/mumbai/versions.json")['v2.0-alpha'].contracts;
const { getTag } = require("./Helpers");

// Place holder addresses
const KOVAN_ADDRESS_RESOLVER = '0x823bE81bbF96BEc0e25CA13170F5AaCb5B79ba83';
const TESTNET_DAO = '0xab0c25f17e993F90CaAaec06514A2cc28DEC340b';

const sushiswapV2Router = "0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506";
const sushiswapFactory = "0xc35DADB65012eC5796536bD9864eD8773aBc74C4";

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
  const artifacts = hre.artifacts

  let network = await ethers.provider.getNetwork()
  console.log('network:', network)

  const signer = (await ethers.getSigners())[0]

  // should be changed with real manager and dao address
  const manager = (await ethers.getSigners())[0]
  const dao = (await ethers.getSigners())[0]

  console.log('signer address: ', signer.address)
  console.log('manager address: ', manager.address)
  console.log('dao address: ', dao.address)

  const ITestUSDT = await artifacts.readArtifact("TestUSDT");
  const tUSDT = await ethers.getContractAt(ITestUSDT.abi, versions.TestUSDT)
  console.log("TestUSDT at", tUSDT.address);

  const ITestUSDC = await artifacts.readArtifact("TestUSDC");
  const tUSDC = await ethers.getContractAt(ITestUSDC.abi, versions.TestUSDC)
  console.log("TestUSDC at", tUSDC.address);

  const ITestWETH = await artifacts.readArtifact("TestWETH");
  const tWETH = await ethers.getContractAt(ITestWETH.abi, versions.TestWETH)
  console.log("TestWETH at", tWETH.address);

  const IPoolLogic = await artifacts.readArtifact("PoolLogic");
  const poolLogic = await ethers.getContractAt(IPoolLogic.abi, versions.PoolLogic)
  console.log("PoolLogic at", tWETH.address);

  const IPoolManagerLogic = await artifacts.readArtifact("PoolManagerLogic");
  const poolManagerLogic = await ethers.getContractAt(IPoolManagerLogic.abi, versions.PoolManagerLogic)
  console.log("PoolManagerLogic at", tWETH.address);

  const AssetHandlerLogic = await ethers.getContractFactory('AssetHandler');

  const PoolFactory = await ethers.getContractFactory("PoolFactory");
  const poolFactory = await upgrades.upgradeProxy(
    versions.PoolFactoryProxy,
    PoolFactory
  );
  console.log("PoolFactoryProxy at", poolFactory.address);

  // Initialize Asset Price Consumer
  const assetWeth = { asset: tWETH.address, assetType: 0, aggregator: eth_price_feed };
  const assetUsdt = { asset: tUSDT.address, assetType: 0, aggregator: usdt_price_feed };
  const assetUsdc = { asset: tUSDC.address, assetType: 0, aggregator: usdc_price_feed };
  const assetHandlerInitAssets = [assetWeth, assetUsdt, assetUsdc];

  const assetHandler = await upgrades.deployProxy(AssetHandlerLogic, [poolFactory.address, assetHandlerInitAssets]);
  await assetHandler.deployed();
  await poolFactory.setAssetHandler(assetHandler.address);
  console.log("AssetHandler deployed at ", assetHandler.address);

  const ERC20Guard = await ethers.getContractFactory("ERC20Guard");
  const erc20Guard = await ERC20Guard.deploy();
  erc20Guard.deployed();
  console.log("ERC20Guard deployed at", erc20Guard.address);

  const UniswapV2RouterGuard = await ethers.getContractFactory("UniswapV2RouterGuard");
  const uniswapV2RouterGuard = await UniswapV2RouterGuard.deploy(sushiswapFactory);
  uniswapV2RouterGuard.deployed();
  console.log("UniswapV2RouterGuard deployed at", uniswapV2RouterGuard.address);

  await poolFactory.connect(dao).setAssetGuard(0, erc20Guard.address);
  await poolFactory.connect(dao).setContractGuard(sushiswapV2Router, uniswapV2RouterGuard.address);
  console.log("PoolFactory set dao", dao.address);

  let tag = await getTag();
  versions = require("../publish/mumbai/versions.json");
  versions[tag] = {
    "tag": tag,
    "network": network,
    "date": new Date().toUTCString(),
    "contracts": {
      "TestUSDT": tUSDT.address,
      "TestUSDC": tUSDC.address,
      "TestWETH": tWETH.address,
      "USDT-Aggregator": usdt_price_feed,
      "USDC-Aggregator": usdc_price_feed,
      "ETH-Aggregator": eth_price_feed,
      "PoolFactoryProxy": poolFactory.address,
      "PoolLogic": poolLogic.address,
      "PoolManagerLogic": poolManagerLogic.address,
      "AssetHandlerProxy": assetHandler.address,
      "ERC20Guard": erc20Guard.address,
      "UniswapV2RouterGuard": uniswapV2RouterGuard.address,
    }
  }

  // convert JSON object to string
  const data = JSON.stringify(versions, null, 2);
  console.log(data)

  fs.writeFileSync('publish/mumbai/versions.json', data);

  // this is for testing to check if upgrade is success
  /*
  console.log('testing...')
  await poolFactory.createFund(
    false, manager.address, 'Barren Wuffet', 'Test Fund', "DHTF", new ethers.BigNumber.from('5000'), [[tUSDC.address, true], [tUSDT.address, true], [tWETH.address, true]]
  )

  const deployedFunds = await poolFactory.getDeployedFunds()
  const length = deployedFunds.length;
  console.log('deployedFundsLength', length)
  const fundAddress = deployedFunds[length - 1]
  const poolLogicProxy = await PoolLogic.attach(fundAddress);
  const poolManagerLogicProxyAddress = await poolLogicProxy.poolManagerLogic();
  const poolManagerLogicProxy = await PoolManagerLogic.attach(poolManagerLogicProxyAddress);

  console.log(await poolManagerLogicProxy.manager(), manager.address)

  console.log('approve')
  await tUSDC.approve(poolLogicProxy.address, 10e6.toString());

  console.log('setChainlinkTimeout')
  await assetHandler.setChainlinkTimeout(90000000);

  console.log('deposit')
  await poolLogicProxy.deposit(tUSDC.address, 10e6.toString());

  const IERC20 = await artifacts.readArtifact("IERC20");
  const iERC20 = new ethers.utils.Interface(IERC20.abi);
  approveABI = iERC20.encodeFunctionData("approve", [sushiswapV2Router, 10e6.toString()]);
  console.log('approve')
  await poolLogicProxy.connect(manager).execTransaction(tUSDC.address, approveABI);
  
  console.log('swap')
  const IUniswapV2Router = await artifacts.readArtifact("IUniswapV2Router");
  const iSushiswapV2Router = new ethers.utils.Interface(IUniswapV2Router.abi);
  swapABI = iSushiswapV2Router.encodeFunctionData("swapExactTokensForTokens", [10e6.toString(), 0, [tUSDC.address, tWETH.address], poolLogicProxy.address, Math.floor(Date.now() / 1000 + 100000000)]);
  await poolLogicProxy.connect(manager).execTransaction(sushiswapV2Router, swapABI);

  console.log('withdraw')
  ethers.provider.send("evm_increaseTime", [3600 * 24])
  await poolLogicProxy.withdraw(5e18.toString())
  */
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error)
    process.exit(1)
  })

