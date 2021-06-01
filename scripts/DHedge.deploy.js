const hre = require('hardhat')
// Place holder addresses
const KOVAN_ADDRESS_RESOLVER = '0xb08b62e1cdfd37eCCd69A9ACe67322CCF801b3A6';
const TESTNET_DAO = '0xab0c25f17e993F90CaAaec06514A2cc28DEC340b';

const synthetixContract = "0x35725C94f3B1aB6BbD533c0B6Df525537d422c5F";

const eth_price_feed = "0xCb7895bDC70A1a1Dce69b689FD7e43A627475A06";
const snx_price_feed = "0xd9E9047ED2d6e2130395a2Fe08033e756CC7e288";
const btc_price_feed = "0x81AE7F8fF54070C52f0eB4EB5b8890e1506AA4f4";
const link_price_feed = "0xb37aA79EBc31B93864Bff2d5390b385bE482897b";
const uni_price_feed = "0xbac904786e476632e75fC6214C797fA80cce9311";
const aave_price_feed = "0xc051eCEaFd546e0Eb915a97F4D0643BEd7F98a11";

const ProxysETH = "0x94B41091eB29b36003aC1C6f0E55a5225633c884";
const ProxysAAVE = "0x503e91fc2b9Ad7453700130d0825E661565E4c3b";
const ProxysUNI = "0x3E88bFAbDCd2b336C4a430262809Cf4a0AC5cd57";
const ProxysLINK = "0xe2B26511C64FE18Acc0BE8EA7c888cDFcacD846E";
const ProxysBTC = "0x23F608ACc41bd7BCC617a01a9202214EE305439a";
const ProxyERC20sUSD = "0xaA5068dC2B3AADE533d3e52C6eeaadC6a8154c57";

async function main () {
  const ethers = hre.ethers
  const l2ethers = hre.l2ethers

  let network = await ethers.provider.getNetwork()
  console.log('network:', network)

  const signer = (await ethers.getSigners())[0]
  console.log('signer address: ', await signer.getAddress())

  // const ERC20Asset = await ethers.getContractFactory('ERC20Asset');
  // const sUSD = await ERC20Asset.deploy("sUSD", "SUSD");
  // console.log("sUSD deployed at ", sUSD.address);

  const AssetHandlerLogic = await ethers.getContractFactory('AssetHandler');
  const assetHandlerLogic = await AssetHandlerLogic.deploy();
  console.log("AssetHandler deployed at ", assetHandlerLogic.address);

  // Deploy PoolLogic
  const PoolLogic = await l2ethers.getContractFactory('PoolLogic')
  const poolLogic = await PoolLogic.deploy()
  tx = await poolLogic.deployed()
  console.log("tx: ", tx.deployTransaction.hash)
  console.log('poolLogic deployed to:', poolLogic.address)
  console.log(
    'deployed bytecode:',
    await ethers.provider.getCode(poolLogic.address)
  )
  console.log('tokenPriceAtLastFeeMint:', await poolLogic.tokenPriceAtLastFeeMint())

  // Deploy PoolManagerLogic
  const PoolManagerLogic = await l2ethers.getContractFactory('PoolManagerLogic')
  const poolManagerLogic = await PoolManagerLogic.deploy()
  tx = await poolManagerLogic.deployed()
  console.log("tx: ", tx.deployTransaction.hash)
  console.log('PoolManagerLogic deployed to:', poolManagerLogic.address)
  console.log(
    'deployed bytecode:',
    await ethers.provider.getCode(poolManagerLogic.address)
  )
  console.log('numberOfSupportedAssets:', await poolManagerLogic.numberOfSupportedAssets())

  // Deploy PoolFactoryLogic
  const PoolFactoryLogic = await l2ethers.getContractFactory('PoolFactory')
  const poolFactoryLogic = await PoolFactoryLogic.deploy()
  let tx = await poolFactoryLogic.deployed()
  console.log("tx: ", tx.deployTransaction.hash)
  console.log('poolFactoryLogic deployed to:', poolFactoryLogic.address)
  console.log(
    'deployed bytecode:',
    await ethers.provider.getCode(poolFactoryLogic.address)
  )

  // Deploy ProxyAdmin
  const ProxyAdmin = await l2ethers.getContractFactory('ProxyAdmin')
  const proxyAdmin = await ProxyAdmin.deploy()
  tx = await proxyAdmin.deployed()

  console.log('ProxyAdmin deployed to:', proxyAdmin.address)
  console.log("tx: ", tx.deployTransaction.hash)
  console.log(
    'deployed bytecode:',
    await ethers.provider.getCode(proxyAdmin.address)
  )

  console.log('ProxyAdmin owner:', await proxyAdmin.owner())

  // Deploy AssetHandlerProxy
  const AssetHandlerProxy = await ethers.getContractFactory('OZProxy');
  const assetHandlerProxy = await AssetHandlerProxy.deploy(assetHandlerLogic.address, proxyAdmin.address, '0x');
  await assetHandlerProxy.deployed();
  console.log("AssetHandlerProxy deployed at ", assetHandlerProxy.address);

  const assetHandler = await AssetHandlerLogic.attach(assetHandlerProxy.address);

  // Deploy poolFactory Proxy
  const PoolFactoryProxy = await l2ethers.getContractFactory('OZProxy')
  const poolFactoryProxy = await PoolFactoryProxy.deploy(poolFactoryLogic.address, proxyAdmin.address, "0x")
  tx = await poolFactoryProxy.deployed()

  console.log('poolFactoryProxy deployed to:', poolFactoryProxy.address)
  console.log("tx: ", tx.deployTransaction.hash)
  console.log(
    'deployed bytecode:',
    await ethers.provider.getCode(poolFactoryProxy.address)
  )

  // Initialize Asset Price Consumer
  // const assetsusd = { asset: ProxyERC20sUSD, assetType: 1, aggregator: eth_price_feed };
  const assetseth = { asset: ProxysETH, assetType: 1, aggregator: eth_price_feed };
  const assetslink = { asset: ProxysLINK, assetType: 1, aggregator: link_price_feed };
  const assetHandlerInitAssets = [assetWeth, assetUsdt, assetUsdc];

  await assetHandler.initialize(poolFactory.address, assetHandlerInitAssets);
  await assetHandler.deployed();
  console.log("AssetHandler initialized");

  const poolFactory = await PoolFactoryLogic.attach(poolFactoryProxy.address)
  tx = await poolFactory.initialize(poolLogic.address, poolManagerLogic.address, assetHandlerProxy.address, dao.address);
  console.log("tx: ", tx.hash)

  const ERC20Guard = await ethers.getContractFactory("ERC20Guard");
  const erc20Guard = await ERC20Guard.deploy();
  erc20Guard.deployed();
  console.log("ERC20Guard deployed at ", erc20Guard.address);

  const SynthetixGuard = await ethers.getContractFactory("SynthetixGuard");
  const synthetixGuard = await SynthetixGuard.deploy();
  synthetixGuard.deployed();
  console.log("synthetixGuard deployed at ", synthetixGuard.address);

  await poolFactory.setAssetGuard(0, erc20Guard.address);
  await poolFactory.setContractGuard(synthetixContract, synthetixGuard.address);

  // Transfer owership to DAO
  // await poolFactory.transferOwnership(TESTNET_DAO);

  // await proxyAdmin.transferOwnership(TESTNET_DAO);

  let versions = {
    "v2.0.0-rc.1": {
      "tag": "v2.0.0-rc.1",
      "fulltag": "v2.0.0-rc.1",
      "network": network,
      "date": new Date(),
      "contracts": {
        "ETH-Aggregator": eth_price_feed,
        "LINK-Aggregator": link_price_feed,
        "ProxyAdmin": proxyAdmin.address,
        "PoolFactoryProxy": poolFactory.address,
        "PoolLogic": poolLogic.address,
        "PoolManagerLogic": poolManagerLogic.address,
        "AssetHandlerProxy": assetHandlerProxy.address,
        "ERC20Guard": erc20Guard.address,
        "synthetixGuard": synthetixGuard.address,
      }
    }
  }

  // convert JSON object to string
  const data = JSON.stringify(versions, null, 2);
  console.log(data)
  fs = require('fs');
  fs.writeFileSync('versions.json', data, function (err) {
    if (err) return console.log(err);
  });

}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error)
    process.exit(1)
  })
