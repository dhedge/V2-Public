const hre = require("hardhat");
const fs = require("fs");
const { getTag } = require("../Helpers");
const Decimal = require("decimal.js");
const csv = require("csvtojson");
const { toBytes32 } = require("../../test/TestHelpers");

// Place holder addresses
const KOVAN_ADDRESS_RESOLVER = "0x823bE81bbF96BEc0e25CA13170F5AaCb5B79ba83";
const TESTNET_DAO = "0xab0c25f17e993F90CaAaec06514A2cc28DEC340b";

// Polygon addresses
const protocolDao = "0xc715Aa67866A2FEF297B12Cb26E953481AeD2df4";
const uberPool = "0x6f005cbceC52FFb28aF046Fd48CB8D6d19FD25E3";
const proxyAdminAddress = "0x0C0a10C9785a73018077dBC74B2A006695849252";

// sushiswap
const sushiswapV2Factory = "0xc35DADB65012eC5796536bD9864eD8773aBc74C4";
const sushiswapV2Router = "0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506";
const sushiMiniChefV2 = "0x0769fd68dFb93167989C6f7254cd0D766Fb2841F";

// aave
const aaveProtocolDataProvider = "0x7551b5D2763519d4e37e8B81929D336De671d46d";
const aaveLendingPool = "0x8dFf5E27EA6b7AC08EbFdf9eB090F32ee9a30fcf";
const aaveIncentivesController = "0x357D51124f59836DeD84c8a1730D72B749d8BC23";

// balancer
const balancerV2Vault = "0xBA12222222228d8Ba445958a75a0704d566BF2C8";

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
const implementationStorage = "0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc";

const prodVersionFile = "./publish/matic/versions.json";
const stagingVersionFile = "./publish/matic/staging-versions.json";

const prodFileName = "./config/prod/dHEDGE Assets list - Polygon.csv";
const stagingFileName = "./config/staging/dHEDGE Assets list - Polygon Staging.csv";

const prodBalancerConfig = require("../../config/prod/dHEDGE Asset list - Polygon Balancer LP.json");
const stagingBalancerConfig = require("../../config/staging/dHEDGE Asset list - Polygon Balancer LP Staging.json");

const stagingExternalAssetFileName = "./config/staging/dHEDGE Assets list - Polygon External Staging.csv";
const prodExternalAssetFileName = "./config/prod/dHEDGE Assets list - Polygon External.csv";

const quickStakingRewardsFactory = "0x5eec262B05A57da9beb5FE96a34aa4eD0C5e029f";
const quickLpUsdcWethStakingRewards = "0x4A73218eF2e820987c59F838906A82455F42D98b";

const deployBalancerV2LpAggregator = async (factory, info) => {
  const ether = "1000000000000000000";
  const divisor = info.weights.reduce((acc, w, i) => {
    if (i == 0) {
      return new Decimal(w).pow(w);
    }
    return acc.mul(new Decimal(w).pow(w));
  }, new Decimal("0"));

  const K = new Decimal(ether).div(divisor).toFixed(0);

  let matrix = [];
  for (let i = 1; i <= 20; i++) {
    const elements = [new Decimal(10).pow(i).times(ether).toFixed(0)];
    for (let j = 0; j < info.weights.length; j++) {
      elements.push(new Decimal(10).pow(i).pow(info.weights[j]).times(ether).toFixed(0));
    }
    matrix.push(elements);
  }

  const BalancerV2LPAggregator = await ethers.getContractFactory("BalancerV2LPAggregator");
  return await BalancerV2LPAggregator.deploy(
    factory,
    balancerV2Vault,
    info.pool,
    info.tokens,
    info.decimals,
    info.weights.map((w) =>
      ethers.BigNumber.from(10)
        .pow(10)
        .mul(w * 100000000),
    ),
    [
      "50000000000000000", // maxPriceDeviation: 0.05
      K,
      "100000000", // powerPrecision
      matrix, // approximationMatrix
    ],
  );
};

const deploy = async (env) => {
  const ethers = hre.ethers;
  const provider = ethers.provider;
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
  const governance = await Governance.deploy();
  console.log("governance deployed to:", governance.address);

  const PoolLogic = await ethers.getContractFactory("PoolLogic");
  const poolLogic = await PoolLogic.deploy();
  console.log("PoolLogic deployed at ", poolLogic.address);

  const PoolManagerLogic = await ethers.getContractFactory("PoolManagerLogic");
  const poolManagerLogic = await PoolManagerLogic.deploy();
  console.log("PoolManagerLogic deployed at ", poolManagerLogic.address);

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
  const poolFactory = await upgrades.deployProxy(PoolFactory, [
    poolLogic.address,
    poolManagerLogic.address,
    assetHandler.address,
    dao.address,
    governance.address,
  ]);
  await poolFactory.deployed();
  console.log("PoolFactoryProxy deployed at ", poolFactory.address);

  const poolLogicProxy = await upgrades.deployProxy(PoolLogic, [poolFactory.address, false, "NA", "NA"]);
  console.log("poolLogicProxy deployed at ", poolLogicProxy.address);
  let poolLogicAddress = await provider.getStorageAt(poolLogicProxy.address, implementationStorage);
  poolLogicAddress = ethers.utils.hexValue(poolLogicAddress);

  const assets = await csv().fromFile(env === "staging" ? stagingFileName : prodFileName);

  const UniV2LPAggregator = await ethers.getContractFactory("UniV2LPAggregator");
  let assetHandlerInitAssets = [];
  for (let i = 0; i < assets.length; i++) {
    const asset = assets[i];
    const assetType = asset.AssetType;
    switch (assetType) {
      case "2":
        // Deploy Sushi LP Aggregator
        console.log("Deploying ", asset["Asset Name"]);
        const sushiLPAggregator = await UniV2LPAggregator.deploy(asset.Address, poolFactory.address);
        await sushiLPAggregator.deployed();
        console.log(`${asset["Asset Name"]} UniV2LPAggregator deployed at `, sushiLPAggregator.address);
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

  const balancerLps = env === "staging" ? stagingBalancerConfig : prodBalancerConfig;
  for (let i = 0; i < balancerLps.length; i++) {
    const balancerLp = balancerLps[i];

    // Deploy Balancer LP Aggregator
    console.log("Deploying ", balancerLp.name);
    const balancerV2Aggregator = await deployBalancerV2LpAggregator(poolFactory.address, balancerLp.data);
    await balancerV2Aggregator.deployed();
    console.log(`${balancerLp.name} BalancerV2LPAggregator deployed at `, balancerV2Aggregator.address);
    assetHandlerInitAssets.push({
      name: balancerLp.name,
      asset: balancerLp.data.pool,
      assetType: 6,
      aggregator: balancerV2Aggregator.address,
    });
  }

  await assetHandler.addAssets(assetHandlerInitAssets);

  const poolManagerLogicProxy = await upgrades.deployProxy(PoolManagerLogic, [
    poolFactory.address,
    manager.address,
    "NA",
    poolLogicAddress,
    "1000",
    [[wmatic, true]],
  ]);
  console.log("poolManagerLogicProxy deployed at ", poolManagerLogicProxy.address);
  let poolManagerLogicAddress = await provider.getStorageAt(poolManagerLogicProxy.address, implementationStorage);
  poolManagerLogicAddress = ethers.utils.hexValue(poolManagerLogicAddress);

  const ERC20Guard = await ethers.getContractFactory("ERC20Guard");
  const erc20Guard = await ERC20Guard.deploy();
  await erc20Guard.deployed();
  console.log("ERC20Guard deployed at ", erc20Guard.address);

  const UniswapV2RouterGuard = await ethers.getContractFactory("UniswapV2RouterGuard");
  const uniswapV2RouterGuard = await UniswapV2RouterGuard.deploy(2, 100); // set slippage 2%
  await uniswapV2RouterGuard.deployed();
  console.log("UniswapV2RouterGuard deployed at ", uniswapV2RouterGuard.address);

  const SushiMiniChefV2Guard = await ethers.getContractFactory("SushiMiniChefV2Guard");
  sushiMiniChefV2Guard = await SushiMiniChefV2Guard.deploy(sushiToken, wmatic);
  await sushiMiniChefV2Guard.deployed();
  console.log("SushiMiniChefV2Guard deployed at ", sushiMiniChefV2Guard.address);

  const SushiLPAssetGuard = await ethers.getContractFactory("SushiLPAssetGuard");
  const sushiLPAssetGuard = await SushiLPAssetGuard.deploy(sushiMiniChefV2); // initialise with Sushi staking pool Id
  await sushiLPAssetGuard.deployed();
  console.log("SushiLPAssetGuard deployed at ", sushiLPAssetGuard.address);

  const csvAssets = await csv().fromFile(env === "staging" ? stagingExternalAssetFileName : prodExternalAssetFileName);
  const addresses = csvAssets.map((asset) => asset.Address);
  const OpenAssetGuard = await ethers.getContractFactory("OpenAssetGuard");
  const openAssetGuard = await OpenAssetGuard.deploy([...addresses]);
  await openAssetGuard.deployed();
  console.log("OpenAssetGuard deployed at ", openAssetGuard.address);

  const QuickLPAssetGuard = await ethers.getContractFactory("QuickLPAssetGuard");
  const quickLPAssetGuard = await QuickLPAssetGuard.deploy(quickStakingRewardsFactory);
  await quickLPAssetGuard.deployed();
  console.log("quickLPAssetGuard deployed at ", quickLPAssetGuard.address);

  const QuickStakingRewardsGuard = await ethers.getContractFactory("QuickStakingRewardsGuard");
  quickStakingRewardsGuard = await QuickStakingRewardsGuard.deploy();
  await quickStakingRewardsGuard.deployed();
  console.log("quickStakingRewardsGuard deployed at ", quickStakingRewardsGuard.address);

  const BalancerV2Guard = await ethers.getContractFactory("BalancerV2Guard");
  balancerV2Guard = await BalancerV2Guard.deploy(2, 100); // set slippage 2%
  await balancerV2Guard.deployed();

  await governance.setAssetGuard(0, erc20Guard.address);
  await governance.setAssetGuard(2, sushiLPAssetGuard.address);
  await governance.setAssetGuard(5, quickLPAssetGuard.address);
  await governance.setContractGuard(sushiswapV2Router, uniswapV2RouterGuard.address);
  await governance.setContractGuard(sushiMiniChefV2, sushiMiniChefV2Guard.address);
  await governance.setContractGuard(quickLpUsdcWethStakingRewards, quickStakingRewardsGuard.address);
  await governance.setContractGuard(balancerV2Vault, balancerV2Guard.address);

  let tag = await getTag();
  let versions = new Object();
  versions[tag] = {
    network: network,
    date: new Date().toUTCString(),
    contracts: {
      Assets: assetHandlerInitAssets,
      Governance: governance.address,
      PoolFactoryProxy: poolFactory.address,
      PoolLogicProxy: poolLogicProxy.address,
      PoolLogic: poolLogicAddress,
      PoolManagerLogicProxy: poolManagerLogicProxy.address,
      PoolManagerLogic: poolManagerLogicAddress,
      AssetHandlerProxy: assetHandler.address,
      ERC20Guard: erc20Guard.address,
      UniswapV2RouterGuard: uniswapV2RouterGuard.address,
      SushiMiniChefV2Guard: sushiMiniChefV2Guard.address,
      SushiLPAssetGuard: sushiLPAssetGuard.address,
      OpenAssetGuard: openAssetGuard.address,
      quickStakingRewardsGuard: quickStakingRewardsGuard.address,
      balancerV2Guard: balancerV2Guard.address,
    },
  };

  if (env === "staging") {
    // Aave
    const AaveLendingPoolAssetGuard = await ethers.getContractFactory("AaveLendingPoolAssetGuard");
    const aaveLendingPoolAssetGuard = await AaveLendingPoolAssetGuard.deploy(aaveProtocolDataProvider);
    await aaveLendingPoolAssetGuard.deployed();
    console.log("AaveLendingPoolAssetGuard deployed at ", aaveLendingPoolAssetGuard.address);

    const AaveLendingPoolGuard = await ethers.getContractFactory("AaveLendingPoolGuard");
    const aaveLendingPoolGuard = await AaveLendingPoolGuard.deploy();
    await aaveLendingPoolGuard.deployed();
    console.log("AaveLendingPoolGuard deployed at ", aaveLendingPoolGuard.address);

    const LendingEnabledAssetGuard = await ethers.getContractFactory("LendingEnabledAssetGuard");
    const lendingEnabledAssetGuard = await LendingEnabledAssetGuard.deploy();
    await lendingEnabledAssetGuard.deployed();
    console.log("LendingEnabledAssetGuard deployed at ", lendingEnabledAssetGuard.address);

    const AaveIncentivesControllerGuard = await ethers.getContractFactory("AaveIncentivesControllerGuard");
    const aaveIncentivesControllerGuard = await AaveIncentivesControllerGuard.deploy(wmatic);
    await aaveIncentivesControllerGuard.deployed();
    console.log("AaveIncentivesControllerGuard deployed at ", aaveIncentivesControllerGuard.address);

    await governance.setAssetGuard(3, aaveLendingPoolAssetGuard.address);
    await governance.setAssetGuard(4, lendingEnabledAssetGuard.address);
    await governance.setContractGuard(aaveLendingPool, aaveLendingPoolGuard.address);
    await governance.setContractGuard(aaveIncentivesController, aaveIncentivesControllerGuard.address);
    await governance.setAddresses([
      [toBytes32("swapRouter"), sushiswapV2Router],
      [toBytes32("aaveProtocolDataProvider"), aaveProtocolDataProvider],
      [toBytes32("weth"), weth],
      [toBytes32("openAssetGuard"), openAssetGuard.address],
    ]);

    aaveContracts = {
      AaveLendingPoolAssetGuard: aaveLendingPoolAssetGuard.address,
      AaveLendingPoolGuard: aaveLendingPoolGuard.address,
      LendingEnabledAssetGuard: lendingEnabledAssetGuard.address,
      AaveIncentivesControllerGuard: aaveIncentivesControllerGuard.address,
    };

    versions[tag].contracts = { ...versions[tag].contracts, ...aaveContracts };

    const USDPriceAggregator = await ethers.getContractFactory("USDPriceAggregator");
    usdPriceAggregator = await USDPriceAggregator.deploy();
    console.log("USDPriceAggregator deployed at ", usdPriceAggregator.address);
    const lendingPoolAsset = {
      name: "Lending Pool",
      asset: aaveLendingPool,
      assetType: 3,
      aggregator: usdPriceAggregator.address,
    };
    await assetHandler.addAssets([lendingPoolAsset]);
  }

  // DAO Settings
  await poolFactory.setDAOAddress(uberPool);
  await poolFactory.transferOwnership(protocolDao);
  await governance.transferOwnership(protocolDao);
  await assetHandler.transferOwnership(protocolDao);
  await sushiLPAssetGuard.transferOwnership(protocolDao);
  await uniswapV2RouterGuard.transferOwnership(protocolDao);
  await openAssetGuard.transferOwnership(protocolDao);
  await quickLPAssetGuard.transferOwnership(protocolDao);

  // convert JSON object to string
  const data = JSON.stringify(versions, null, 2);
  console.log(data);

  versionFile = env === "prod" ? productionVersionFile : stagingVersionFile;
  fs.writeFileSync(versionFile, data);
};

module.exports = { deploy };
