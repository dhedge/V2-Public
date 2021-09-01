const fs = require("fs");
const csv = require("csvtojson");
const { writeCsv, getTag, hasDuplicates, tryVerify } = require("./Helpers");
const Safe = require("@gnosis.pm/safe-core-sdk");
const { EthersAdapter } = require("@gnosis.pm/safe-core-sdk");
const { SafeService } = require("@gnosis.pm/safe-ethers-adapters");
const proxyAdminAddress = "0x0C0a10C9785a73018077dBC74B2A006695849252";
const safeAddress = "0xc715Aa67866A2FEF297B12Cb26E953481AeD2df4";
// https://github.com/gnosis/safe-deployments/blob/main/src/assets/v1.3.0/multi_send.json#L13
const multiSendAddress = "0xA238CBeb142c10Ef7Ad8442C6D1f9E89e07e7761";
const service = new SafeService("https://safe-transaction.polygon.gnosis.io");

// File Names
const stagingAssetFileName = "./config/staging/dHEDGE Assets list - Polygon Staging.csv";
const prodAssetFileName = "./config/prod/dHEDGE Assets list - Polygon.csv";
const stagingAssetGuardFileName = "./config/staging/dHEDGE Governance Asset Guards - Polygon Staging.csv";
const prodAssetGuardFileName = "./config/prod/dHEDGE Governance Asset Guards - Polygon.csv";
const stagingContractGuardFileName = "./config/staging/dHEDGE Governance Contract Guards - Polygon Staging.csv";
const prodContractGuardFileName = "./config/prod/dHEDGE Governance Contract Guards - Polygon.csv";
const stagingGovernanceNamesFileName = "./config/staging/dHEDGE Governance Names - Polygon Staging.csv";
const prodGovernanceNamesFileName = "./config/prod/dHEDGE Governance Names - Polygon.csv";
const stagingExternalAssetFileName = "./config/staging/dHEDGE Assets list - Polygon External Staging.csv";
const prodExternalAssetFileName = "./config/prod/dHEDGE Assets list - Polygon External.csv";

// Addresses
const aaveProtocolDataProvider = "0x7551b5D2763519d4e37e8B81929D336De671d46d";
const sushiswapV2Router = "0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506";
const quickswapRouter = "0xa5E0829CaCEd8fFDD4De3c43696c57F7D7A678ff";
const protocolDao = "0xc715Aa67866A2FEF297B12Cb26E953481AeD2df4";
const quickStakingRewardsFactory = "0x5eec262B05A57da9beb5FE96a34aa4eD0C5e029f";
const quickLpUsdcWethStakingRewards = "0x4A73218eF2e820987c59F838906A82455F42D98b";
const aaveIncentivesController = "0x357D51124f59836DeD84c8a1730D72B749d8BC23";
const aaveLendingPool = "0x8dFf5E27EA6b7AC08EbFdf9eB090F32ee9a30fcf";
let sushiToken, wmatic;
const sushiMiniChefV2 = "0x0769fd68dFb93167989C6f7254cd0D766Fb2841F";
let nonce,
  safeSdk,
  nonceLog = new Array();

const proposeTx = async (to, data, message) => {
  const transaction = {
    to: to,
    value: "0",
    data: data,
    nonce: nonce,
  };

  nonceLog.push({
    nonce: nonce,
    message: message,
  });

  console.log("Proposing transaction: ", transaction);
  console.log(`Nonce ${nonce}: ${message}`);

  nonce += 1;

  const safeTransaction = await safeSdk.createTransaction(...[transaction]);
  // off-chain sign
  const txHash = await safeSdk.getTransactionHash(safeTransaction);
  const signature = await safeSdk.signTransactionHash(txHash);
  // on-chain sign
  // const approveTxResponse = await safeSdk.approveTransactionHash(txHash)
  // console.log("approveTxResponse", approveTxResponse);
  console.log("safeTransaction: ", safeTransaction);

  await service.proposeTx(safeAddress, txHash, safeTransaction, signature);
};

task("upgrade", "Upgrade contracts")
  .addOptionalParam("poolFactory", "upgrade poolFactory", false, types.boolean)
  .addOptionalParam("assetHandler", "upgrade assetHandler", false, types.boolean)
  .addOptionalParam("poolLogic", "upgrade poolLogic", false, types.boolean)
  .addOptionalParam("poolManagerLogic", "upgrade poolManagerLogic", false, types.boolean)
  .addOptionalParam("assets", "deploy new assets", true, types.boolean)
  .addOptionalParam("production", "run in production environment", false, types.boolean)
  .addOptionalParam("aaveLendingPoolAssetGuard", "upgrade aaveLendingPoolAssetGuard", false, types.boolean)
  .addOptionalParam("sushiLPAssetGuard", "upgrade sushiLPAssetGuard", false, types.boolean)
  .addOptionalParam("erc20Guard", "upgrade erc20Guard", false, types.boolean)
  .addOptionalParam("lendingEnabledAssetGuard", "upgrade LendingEnabledAssetGuard", false, types.boolean)
  .addOptionalParam("uniswapV2RouterGuard", "upgrade uniswapV2RouterGuard", false, types.boolean)
  .addOptionalParam("openAssetGuard", "upgrade openAssetGuard", false, types.boolean)
  .addOptionalParam("quickLPAssetGuard", "upgrade quickLPAssetGuard", false, types.boolean)
  .addOptionalParam("quickStakingRewardsGuard", "upgrade quickStakingRewardsGuard", false, types.boolean)
  .addOptionalParam("sushiMiniChefV2Guard", "upgrade sushiMiniChefV2Guard", false, types.boolean)
  .addOptionalParam("aaveIncentivesControllerGuard", "upgrade AaveIncentivesControllerGuard", false, types.boolean)
  .addOptionalParam("aaveLendingPoolGuard", "upgrade AaveLendingPoolGuard", false, types.boolean)
  .addOptionalParam("pause", "pause contract", false, types.boolean)
  .addOptionalParam("unpause", "unpause contract", false, types.boolean)
  .setAction(async (taskArgs) => {
    // Initialize the Safe SDK
    const provider = ethers.provider;
    const owner1 = provider.getSigner(0);
    const ethAdapter = new EthersAdapter({ ethers: ethers, signer: owner1 });
    const chainId = await ethAdapter.getChainId();
    const hre = require("hardhat");

    const contractNetworks = {
      [chainId]: {
        multiSendAddress: multiSendAddress,
      },
    };

    safeSdk = await Safe.default.create({
      ethAdapter,
      safeAddress: safeAddress,
      contractNetworks,
    });
    nonce = await safeSdk.getNonce();
    const owner1Address = await owner1.getAddress();

    const network = await ethers.provider.getNetwork();
    console.log("network:", network);

    // Init tag
    const versionFile = taskArgs.production ? "versions" : "staging-versions";
    const versions = require(`../publish/${network.name}/${versionFile}.json`);
    const newTag = await getTag();
    const oldTag = Object.keys(versions)[Object.keys(versions).length - 1];
    console.log(`oldTag: ${oldTag}`);
    console.log(`newTag: ${newTag}`);
    const checkNewVersion = !taskArgs.assets && !taskArgs.pause && !taskArgs.unpause;
    if (checkNewVersion && newTag == oldTag) throw "Error: No new version to upgrade";

    // Init contracts data
    const ProxyAdmin = await hre.artifacts.readArtifact("ProxyAdmin");
    const proxyAdmin = new ethers.utils.Interface(ProxyAdmin.abi);

    const contracts = versions[oldTag].contracts;
    versions[newTag] = new Object();
    versions[newTag].contracts = { ...contracts };
    versions[newTag].network = network;
    versions[newTag].date = new Date().toUTCString();
    let setLogic = false;

    // Governance
    const Governance = await hre.artifacts.readArtifact("Governance");
    const governanceABI = new ethers.utils.Interface(Governance.abi);

    // Asset Guard
    const assetGuardfileName = taskArgs.production ? prodAssetGuardFileName : stagingAssetGuardFileName;
    const csvAssetGuards = await csv().fromFile(assetGuardfileName);
    let newAssetGuards = new Array();

    // Contract Guard
    const contractGuardfileName = taskArgs.production ? prodContractGuardFileName : stagingContractGuardFileName;
    const csvContractGuards = await csv().fromFile(contractGuardfileName);
    let newContractGuards = new Array();

    // Governance names
    const governanceNamesfileName = taskArgs.production ? prodGovernanceNamesFileName : stagingGovernanceNamesFileName;
    const csvGovernanceNames = await csv().fromFile(governanceNamesfileName);
    let newGovernanceNames = new Array();

    // Pause Pool Factory
    let poolFactoryProxy = contracts.PoolFactoryProxy;
    const PoolFactory = await hre.artifacts.readArtifact("PoolFactory");
    const PoolFactoryABI = new ethers.utils.Interface(PoolFactory.abi);

    if (taskArgs.pause) {
      const pauseABI = PoolFactoryABI.encodeFunctionData("pause", []);
      await proposeTx(poolFactoryProxy, pauseABI, "Pause Pool Factory");
    }
    if (taskArgs.assets) {
      // look up to check if csvAsset is in the current versions
      let assetHandlerAssets = [];
      const fileName = taskArgs.production ? prodAssetFileName : stagingAssetFileName;
      const csvAssets = await csv().fromFile(fileName);

      // Check for any accidental duplicate addresses or price feeds in the CSV
      if (await hasDuplicates(csvAssets, "Address")) throw "Duplicate 'Address' field found in assets CSV";
      if (await hasDuplicates(csvAssets, "Chainlink Price Feed"))
        throw "Duplicate 'Chainlink Price Feed' field found in assets CSV";

      const SushiLPAggregator = await ethers.getContractFactory("UniV2LPAggregator");
      for (const csvAsset of csvAssets) {
        let foundInVersions = false;
        for (const asset of contracts.Assets) {
          if (csvAsset["Asset Name"] === "Sushi") sushiToken = csvAsset.Address;
          if (csvAsset["Asset Name"] === "Wrapped Matic") wmatic = csvAsset.Address;
          if (csvAsset["Asset Name"] === asset.name) {
            console.log(`csvAsset: ${csvAsset["Asset Name"]} is already in the current contracts.Assets`);
            foundInVersions = true;
            break;
          }
        }
        if (!foundInVersions) {
          const assetType = csvAsset.AssetType;
          switch (assetType) {
            case "2":
              // Deploy Sushi LP Aggregator
              console.log("Deploying ", csvAsset["Asset Name"]);
              const sushiLPAggregator = await SushiLPAggregator.deploy(csvAsset.Address, contracts.PoolFactoryProxy);
              await sushiLPAggregator.deployed();
              console.log(`${csvAsset["Asset Name"]} SushiLPAggregator deployed at `, sushiLPAggregator.address);
              assetHandlerAssets.push({
                name: csvAsset["Asset Name"],
                asset: csvAsset.Address,
                assetType: assetType,
                aggregator: sushiLPAggregator.address,
              });
              break;
            case "3":
              // Deploy USDPriceAggregator
              const USDPriceAggregator = await ethers.getContractFactory("USDPriceAggregator");
              usdPriceAggregator = await USDPriceAggregator.deploy();
              console.log("USDPriceAggregator deployed at ", usdPriceAggregator.address);
              assetHandlerAssets.push({
                name: csvAsset["Asset Name"],
                asset: csvAsset.Address,
                assetType: assetType,
                aggregator: usdPriceAggregator.address,
              });
              break;
            default:
              console.log(`Adding new asset: ${csvAsset["Asset Name"]}`);
              assetHandlerAssets.push({
                name: csvAsset["Asset Name"],
                asset: csvAsset.Address,
                assetType: assetType,
                aggregator: csvAsset["Chainlink Price Feed"],
              });
          }
        }
      }

      const AssetHandlerLogic = await hre.artifacts.readArtifact("AssetHandler");
      const assetHandlerLogic = new ethers.utils.Interface(AssetHandlerLogic.abi);
      const addAssetsABI = assetHandlerLogic.encodeFunctionData("addAssets", [assetHandlerAssets]);

      if (assetHandlerAssets.length > 0) {
        await proposeTx(contracts.AssetHandlerProxy, addAssetsABI, "Update assets in Asset Handler");
        versions[newTag].contracts.Assets = [...versions[newTag].contracts.Assets, ...assetHandlerAssets];
      }
    }
    if (taskArgs.poolFactory) {
      const PoolFactoryContract = await ethers.getContractFactory("PoolFactory");
      const newPoolFactoryLogic = await upgrades.prepareUpgrade(poolFactoryProxy, PoolFactoryContract);
      console.log("New PoolFactory logic deployed to: ", newPoolFactoryLogic);

      tryVerify(hre, newPoolFactoryLogic, "contracts/PoolFactory.sol:PoolFactory", []);

      const upgradeABI = proxyAdmin.encodeFunctionData("upgrade", [poolFactoryProxy, newPoolFactoryLogic]);
      await proposeTx(proxyAdminAddress, upgradeABI, "Upgrade Pool Factory");
    }
    if (taskArgs.assetHandler) {
      let oldAssetHandler = contracts.AssetHandlerProxy;
      const AssetHandler = await ethers.getContractFactory("AssetHandler");
      const assetHandler = await upgrades.prepareUpgrade(oldAssetHandler, AssetHandler);
      console.log("assetHandler logic deployed to: ", assetHandler);

      tryVerify(hre, assetHandler, "contracts/assets/AssetHandler.sol:AssetHandler", []);

      const upgradeABI = proxyAdmin.encodeFunctionData("upgrade", [oldAssetHandler, assetHandler]);
      await proposeTx(proxyAdminAddress, upgradeABI, "Upgrade Asset Handler");
    }
    if (taskArgs.poolLogic) {
      let oldPooLogicProxy = contracts.PoolLogicProxy;
      const PoolLogic = await ethers.getContractFactory("PoolLogic");
      const poolLogic = await upgrades.prepareUpgrade(oldPooLogicProxy, PoolLogic);
      console.log("poolLogic deployed to: ", poolLogic);
      versions[newTag].contracts.PoolLogic = poolLogic;
      setLogic = true;

      tryVerify(hre, poolLogic, "contracts/PoolLogic.sol:PoolLogic", []);
    }
    if (taskArgs.poolManagerLogic) {
      let oldPooManagerLogicProxy = contracts.PoolManagerLogicProxy;
      const PoolManagerLogic = await ethers.getContractFactory("PoolManagerLogic");
      const poolManagerLogic = await upgrades.prepareUpgrade(oldPooManagerLogicProxy, PoolManagerLogic);
      console.log("poolManagerLogic deployed to: ", poolManagerLogic);
      versions[newTag].contracts.PoolManagerLogic = poolManagerLogic;
      setLogic = true;

      tryVerify(hre, poolManagerLogic, "contracts/PoolManagerLogic.sol:PoolManagerLogic", []);
    }
    if (setLogic) {
      const setLogicABI = PoolFactoryABI.encodeFunctionData("setLogic", [
        versions[newTag].contracts.PoolLogic,
        versions[newTag].contracts.PoolManagerLogic,
      ]);
      await proposeTx(contracts.PoolFactoryProxy, setLogicABI, "Set logic for poolLogic and poolManagerLogic");
    }
    if (taskArgs.aaveLendingPoolAssetGuard) {
      const AaveLendingPoolAssetGuard = await ethers.getContractFactory("AaveLendingPoolAssetGuard");
      const aaveLendingPoolAssetGuard = await AaveLendingPoolAssetGuard.deploy(aaveProtocolDataProvider);
      await aaveLendingPoolAssetGuard.deployed();
      console.log("AaveLendingPoolAssetGuard deployed at ", aaveLendingPoolAssetGuard.address);
      versions[newTag].contracts.AaveLendingPoolAssetGuard = aaveLendingPoolAssetGuard.address;

      tryVerify(
        hre,
        aaveLendingPoolAssetGuard.address,
        "contracts/guards/assetGuards/AaveLendingPoolAssetGuard.sol:AaveLendingPoolAssetGuard",
        [aaveProtocolDataProvider],
      );

      const setAssetGuardABI = governanceABI.encodeFunctionData("setAssetGuard", [
        3,
        aaveLendingPoolAssetGuard.address,
      ]);
      await proposeTx(contracts.Governance, setAssetGuardABI, "setAssetGuard for aaveLendingPoolAssetGuard");
      newAssetGuards.push({
        AssetType: 3,
        GuardName: "AaveLendingPoolAssetGuard",
        GuardAddress: aaveLendingPoolAssetGuard.address,
        Description: "Aave Lending Pool",
      });
    }
    if (taskArgs.sushiLPAssetGuard) {
      const SushiLPAssetGuard = await ethers.getContractFactory("SushiLPAssetGuard");
      const sushiLPAssetGuard = await SushiLPAssetGuard.deploy(sushiMiniChefV2); // initialise with Sushi staking pool Id
      await sushiLPAssetGuard.deployed();
      console.log("SushiLPAssetGuard deployed at ", sushiLPAssetGuard.address);
      versions[newTag].contracts.SushiLPAssetGuard = sushiLPAssetGuard.address;

      tryVerify(
        hre,
        sushiLPAssetGuard.address,
        "contracts/guards/assetGuards/SushiLPAssetGuard.sol:SushiLPAssetGuard",
        [sushiMiniChefV2],
      );

      await sushiLPAssetGuard.transferOwnership(protocolDao);
      const setAssetGuardABI = governanceABI.encodeFunctionData("setAssetGuard", [2, sushiLPAssetGuard.address]);
      await proposeTx(contracts.Governance, setAssetGuardABI, "setAssetGuard for SushiLPAssetGuard");
      newAssetGuards.push({
        AssetType: 2,
        GuardName: "SushiLPAssetGuard",
        GuardAddress: sushiLPAssetGuard.address,
        Description: "Sushi LP tokens",
      });
    }
    if (taskArgs.erc20Guard) {
      const ERC20Guard = await ethers.getContractFactory("ERC20Guard");
      const erc20Guard = await ERC20Guard.deploy();
      await erc20Guard.deployed();
      console.log("ERC20Guard deployed at ", erc20Guard.address);
      versions[newTag].contracts.ERC20Guard = erc20Guard.address;

      tryVerify(hre, erc20Guard.address, "contracts/guards/assetGuards/ERC20Guard.sol:ERC20Guard", []);

      const setAssetGuardABI = governanceABI.encodeFunctionData("setAssetGuard", [0, erc20Guard.address]);
      await proposeTx(contracts.Governance, setAssetGuardABI, "setAssetGuard for ERC20Guard");
      newAssetGuards.push({
        AssetType: 0,
        GuardName: "ERC20Guard",
        GuardAddress: erc20Guard.address,
        Description: "ERC20 tokens",
      });
    }
    if (taskArgs.lendingEnabledAssetGuard) {
      const LendingEnabledAssetGuard = await ethers.getContractFactory("LendingEnabledAssetGuard");
      const lendingEnabledAssetGuard = await LendingEnabledAssetGuard.deploy();
      await lendingEnabledAssetGuard.deployed();
      console.log("LendingEnabledAssetGuard deployed at ", lendingEnabledAssetGuard.address);

      versions[newTag].contracts.LendingEnabledAssetGuard = lendingEnabledAssetGuard.address;

      tryVerify(
        hre,
        lendingEnabledAssetGuard.address,
        "contracts/guards/assetGuards/LendingEnabledAssetGuard.sol:LendingEnabledAssetGuard",
        [],
      );

      const setAssetGuardABI = governanceABI.encodeFunctionData("setAssetGuard", [4, lendingEnabledAssetGuard.address]);
      await proposeTx(contracts.Governance, setAssetGuardABI, "setAssetGuard for LendingEnabledAssetGuard");
      newAssetGuards.push({
        AssetType: 4,
        GuardName: "LendingEnabledAssetGuard",
        GuardAddress: lendingEnabledAssetGuard.address,
        Description: "Lending Enabled Asset tokens",
      });
    }
    if (taskArgs.uniswapV2RouterGuard) {
      const UniswapV2RouterGuard = await ethers.getContractFactory("UniswapV2RouterGuard");
      const uniswapV2RouterGuard = await UniswapV2RouterGuard.deploy(10, 100); // set slippage 10%
      await uniswapV2RouterGuard.deployed();
      console.log("UniswapV2RouterGuard deployed at ", uniswapV2RouterGuard.address);
      versions[newTag].contracts.UniswapV2RouterGuard = uniswapV2RouterGuard.address;

      tryVerify(
        hre,
        uniswapV2RouterGuard.address,
        "contracts/guards/UniswapV2RouterGuard.sol:UniswapV2RouterGuard",
        [10, 100],
      );

      await uniswapV2RouterGuard.transferOwnership(protocolDao);
      let setContractGuardABI = governanceABI.encodeFunctionData("setContractGuard", [
        sushiswapV2Router,
        uniswapV2RouterGuard.address,
      ]);
      await proposeTx(contracts.Governance, setContractGuardABI, "setContractGuard for sushiswapV2Router");
      newContractGuards.push({
        ContractAddress: sushiswapV2Router,
        GuardName: "UniswapV2RouterGuard",
        GuardAddress: uniswapV2RouterGuard.address,
        Description: "Sushi V2 router",
      });

      setContractGuardABI = governanceABI.encodeFunctionData("setContractGuard", [
        quickswapRouter,
        uniswapV2RouterGuard.address,
      ]);
      await proposeTx(contracts.Governance, setContractGuardABI, "setContractGuard for quickswapRouter");
      newContractGuards.push({
        ContractAddress: quickswapRouter,
        GuardName: "UniswapV2RouterGuard",
        GuardAddress: uniswapV2RouterGuard.address,
        Description: "Quickswap V2 router",
      });
    }
    if (taskArgs.openAssetGuard) {
      const fileName = taskArgs.production ? prodExternalAssetFileName : stagingExternalAssetFileName;
      const csvAssets = await csv().fromFile(fileName);
      let addresses = csvAssets.map((asset) => asset.Address);
      const OpenAssetGuard = await ethers.getContractFactory("OpenAssetGuard");
      const openAssetGuard = await OpenAssetGuard.deploy(addresses);
      await openAssetGuard.deployed();
      console.log("OpenAssetGuard deployed at ", openAssetGuard.address);
      versions[newTag].contracts.OpenAssetGuard = openAssetGuard.address;

      tryVerify(hre, openAssetGuard.address, "contracts/guards/assetGuards/OpenAssetGuard.sol:OpenAssetGuard", [
        addresses,
      ]);

      await openAssetGuard.transferOwnership(protocolDao);
      const setAddressesABI = governanceABI.encodeFunctionData("setAddresses", [
        [[ethers.utils.formatBytes32String("openAssetGuard"), openAssetGuard.address]],
      ]);
      await proposeTx(contracts.Governance, setAddressesABI, "setAddresses for openAssetGuard");
      newGovernanceNames.push({
        Name: "openAssetGuard",
        Destination: openAssetGuard.address,
      });
    }
    if (taskArgs.quickLPAssetGuard) {
      const QuickLPAssetGuard = await ethers.getContractFactory("QuickLPAssetGuard");
      const quickLPAssetGuard = await QuickLPAssetGuard.deploy(quickStakingRewardsFactory);
      await quickLPAssetGuard.deployed();
      console.log("quickLPAssetGuard deployed at ", quickLPAssetGuard.address);
      versions[newTag].contracts.QuickLPAssetGuard = quickLPAssetGuard.address;

      tryVerify(
        hre,
        quickLPAssetGuard.address,
        "contracts/guards/assetGuards/QuickLPAssetGuard.sol:QuickLPAssetGuard",
        [quickStakingRewardsFactory],
      );

      await quickLPAssetGuard.transferOwnership(protocolDao);
      const setAssetGuardABI = governanceABI.encodeFunctionData("setAssetGuard", [5, quickLPAssetGuard.address]);
      await proposeTx(contracts.Governance, setAssetGuardABI, "setAssetGuard for quickLPAssetGuard");
      newAssetGuards.push({
        AssetType: 5,
        GuardName: "QuickLPAssetGuard",
        GuardAddress: quickLPAssetGuard.address,
        Description: "Quick LP tokens",
      });
    }
    if (taskArgs.quickStakingRewardsGuard) {
      const QuickStakingRewardsGuard = await ethers.getContractFactory("QuickStakingRewardsGuard");
      const quickStakingRewardsGuard = await QuickStakingRewardsGuard.deploy();
      await quickStakingRewardsGuard.deployed();
      console.log("quickStakingRewardsGuard deployed at ", quickStakingRewardsGuard.address);
      versions[newTag].contracts.QuickStakingRewardsGuard = quickStakingRewardsGuard.address;

      tryVerify(
        hre,
        quickStakingRewardsGuard.address,
        "contracts/guards/QuickStakingRewardsGuard.sol:QuickStakingRewardsGuard",
        [],
      );

      const setContractGuardABI = governanceABI.encodeFunctionData("setContractGuard", [
        quickLpUsdcWethStakingRewards,
        quickStakingRewardsGuard.address,
      ]);
      await proposeTx(contracts.Governance, setContractGuardABI, "setContractGuard for QuickStakingRewardsGuard");
      newContractGuards.push({
        ContractAddress: quickLpUsdcWethStakingRewards,
        GuardName: "QuickStakingRewardsGuard",
        GuardAddress: quickStakingRewardsGuard.address,
        Description: "Quick Staking Reward",
      });
    }
    if (taskArgs.sushiMiniChefV2Guard) {
      const SushiMiniChefV2Guard = await ethers.getContractFactory("SushiMiniChefV2Guard");
      const sushiMiniChefV2Guard = await SushiMiniChefV2Guard.deploy(sushiToken, wmatic);
      await sushiMiniChefV2Guard.deployed();
      console.log("SushiMiniChefV2Guard deployed at ", sushiMiniChefV2Guard.address);
      versions[newTag].contracts.SushiMiniChefV2Guard = sushiMiniChefV2Guard.address;

      tryVerify(hre, sushiMiniChefV2Guard.address, "contracts/guards/SushiMiniChefV2Guard.sol:SushiMiniChefV2Guard", [
        sushiToken,
        wmatic,
      ]);

      const setContractGuardABI = governanceABI.encodeFunctionData("setContractGuard", [
        sushiMiniChefV2,
        sushiMiniChefV2Guard.address,
      ]);
      await proposeTx(contracts.Governance, setContractGuardABI, "setContractGuard for sushiMiniChefV2Guard");
      newContractGuards.push({
        ContractAddress: sushiMiniChefV2,
        GuardName: "SushiMiniChefV2Guard",
        GuardAddress: sushiMiniChefV2Guard.address,
        Description: "Sushi rewards contract",
      });
    }
    if (taskArgs.aaveIncentivesControllerGuard) {
      const AaveIncentivesControllerGuard = await ethers.getContractFactory("AaveIncentivesControllerGuard");
      console.log("wmatic: ", wmatic);
      const aaveIncentivesControllerGuard = await AaveIncentivesControllerGuard.deploy(wmatic);
      await aaveIncentivesControllerGuard.deployed();
      console.log("AaveIncentivesControllerGuard deployed at ", aaveIncentivesControllerGuard.address);
      versions[newTag].contracts.AaveIncentivesControllerGuard = aaveIncentivesControllerGuard.address;

      tryVerify(
        hre,
        aaveIncentivesControllerGuard.address,
        "contracts/guards/AaveIncentivesControllerGuard.sol:AaveIncentivesControllerGuard",
        [wmatic],
      );

      const setContractGuardABI = governanceABI.encodeFunctionData("setContractGuard", [
        aaveIncentivesController,
        aaveIncentivesControllerGuard.address,
      ]);
      await proposeTx(contracts.Governance, setContractGuardABI, "setContractGuard for AaveIncentivesControllerGuard");
      newContractGuards.push({
        ContractAddress: aaveIncentivesController,
        GuardName: "AaveIncentivesControllerGuard",
        GuardAddress: aaveIncentivesControllerGuard.address,
        Description: "Aave Incentives Controller contract",
      });
    }
    if (taskArgs.aaveLendingPoolGuard) {
      const AaveLendingPoolGuard = await ethers.getContractFactory("AaveLendingPoolGuard");
      const aaveLendingPoolGuard = await AaveLendingPoolGuard.deploy();
      await aaveLendingPoolGuard.deployed();
      console.log("AaveLendingPoolGuard deployed at ", aaveLendingPoolGuard.address);
      versions[newTag].contracts.AaveLendingPoolGuard = aaveLendingPoolGuard.address;

      tryVerify(
        hre,
        aaveLendingPoolGuard.address,
        "contracts/guards/AaveLendingPoolGuard.sol:AaveLendingPoolGuard",
        [],
      );

      const setContractGuardABI = governanceABI.encodeFunctionData("setContractGuard", [
        aaveLendingPool,
        aaveLendingPoolGuard.address,
      ]);
      await proposeTx(contracts.Governance, setContractGuardABI, "setContractGuard for aaveLendingPoolGuard");
      newContractGuards.push({
        ContractAddress: aaveLendingPool,
        GuardName: "AaveLendingPoolGuard",
        GuardAddress: aaveLendingPoolGuard.address,
        Description: "Aave Lending Pool contract",
      });
    }
    if (taskArgs.unpause) {
      // Unpause Pool Factory
      const unpauseABI = PoolFactoryABI.encodeFunctionData("unpause", []);
      await proposeTx(poolFactoryProxy, unpauseABI, "Unpause pool Factory");
    }

    // convert JSON object to string
    const data = JSON.stringify(versions, null, 2);
    console.log(data);

    // write to version file
    fs.writeFileSync(`./publish/${network.name}/${versionFile}.json`, data);

    versions[newTag].contracts = { ...contracts };
    let newCsvAssetGuards = new Array();
    let newCsvContractGuards = new Array();
    let newCsvGovernanceNames = new Array();
    for (const newAssetGuard of newAssetGuards) {
      for (const csvAssetGuard of csvAssetGuards) {
        if (newAssetGuard.GuardName == csvAssetGuard.GuardName) {
          newCsvAssetGuards.push(newAssetGuard);
        } else {
          newCsvAssetGuards.push(csvAssetGuard);
        }
      }
    }
    for (const newContractGuard of newContractGuards) {
      for (const csvContractGuard of csvContractGuards) {
        if (newContractGuard.GuardName == csvContractGuard.GuardName) {
          newCsvContractGuards.push(newContractGuard);
        } else {
          newCsvContractGuards.push(csvContractGuard);
        }
      }
    }
    for (const newGovernanceName of newGovernanceNames) {
      for (const csvGovernanceName of csvGovernanceNames) {
        if (newGovernanceName.Name == csvGovernanceName.Name) {
          newCsvGovernanceNames.push(newGovernanceName);
        } else {
          newCsvGovernanceNames.push(csvGovernanceName);
        }
      }
    }
    writeCsv(newCsvAssetGuards, assetGuardfileName);
    writeCsv(newCsvContractGuards, contractGuardfileName);
    writeCsv(newCsvGovernanceNames, governanceNamesfileName);

    console.log(nonceLog);
  });

module.exports = {};
