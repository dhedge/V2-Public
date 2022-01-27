import { task, types } from "hardhat/config";
import { HardhatRuntimeEnvironment } from "hardhat/types";

import fs from "fs";
const csv = require("csvtojson");
import {
  writeCsv,
  getTag,
  hasDuplicates,
  proposeTx,
  nonceLog,
  checkAsset,
  checkBalancerLpAsset,
  getAggregator,
  proxyAdminAddress,
  tryVerify,
} from "../Helpers";
import { dhedgeEasySwapperAddress, uniswapV3 } from "../../config/chainData/polygon-data";

const Decimal = require("decimal.js");

// File Names
const stagingBalancerConfig = require("../../config/staging/dHEDGE Asset list - Polygon Balancer LP Staging.json");
const prodBalancerConfig = require("../../config/prod/dHEDGE Asset list - Polygon Balancer LP.json");
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
const balancerV2Vault = "0xBA12222222228d8Ba445958a75a0704d566BF2C8";
const balancerMerkleOrchard = "0x0F3e0c4218b7b0108a3643cFe9D3ec0d4F57c54e";
const aaveProtocolDataProvider = "0x7551b5D2763519d4e37e8B81929D336De671d46d";
const sushiswapV2Router = "0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506";
const quickswapRouter = "0xa5E0829CaCEd8fFDD4De3c43696c57F7D7A678ff";
const protocolDao = "0xc715Aa67866A2FEF297B12Cb26E953481AeD2df4";
const quickStakingRewardsFactory = "0x5eec262B05A57da9beb5FE96a34aa4eD0C5e029f";
const quickLpUsdcWethStakingRewards = "0x4A73218eF2e820987c59F838906A82455F42D98b";
const aaveIncentivesController = "0x357D51124f59836DeD84c8a1730D72B749d8BC23";
const aaveLendingPool = "0x8dFf5E27EA6b7AC08EbFdf9eB090F32ee9a30fcf";
const oneInchV4Router = "0x1111111254fb6c44bac0bed2854e76f90643097d";
const sushiToken = "0x0b3f868e0be5597d5db7feb59e1cadbb0fdda50a";
const wmatic = "0x0d500b1d8e8ef31e21c99d1db9a6444d3adf1270";
const sushiMiniChefV2 = "0x0769fd68dFb93167989C6f7254cd0D766Fb2841F";

// Misc
const implementationStorage = "0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc";

const deployBalancerV2LpAggregator = async (factory: string, info: any, hre: HardhatRuntimeEnvironment) => {
  const ether = "1000000000000000000";
  const divisor = info.weights.reduce((acc: any, w: any, i: any) => {
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

  await hre.run("compile:one", { contractName: "BalancerV2LPAggregator" });

  const BalancerV2LPAggregator = await hre.ethers.getContractFactory("BalancerV2LPAggregator");

  const balancerV2LpAggregator = await BalancerV2LPAggregator.deploy(
    factory,
    balancerV2Vault,
    info.pool,
    info.tokens,
    info.decimals,
    info.weights.map((w: any) => new Decimal(w).mul(ether).toFixed(0)),
    [
      "50000000000000000", // maxPriceDeviation: 0.05
      K,
      "100000000", // powerPrecision
      matrix, // approximationMatrix
    ] as any,
  );
  await balancerV2LpAggregator.deployed();
  await tryVerify(
    hre,
    balancerV2LpAggregator.address,
    "contracts/assets/BalancerV2LPAggregator.sol:BalancerV2LPAggregator",
    [
      factory,
      balancerV2Vault,
      info.pool,
      info.tokens,
      info.decimals,
      info.weights.map((w: any) => new Decimal(w).mul(ether).toFixed(0)),
      [
        "50000000000000000", // maxPriceDeviation: 0.05
        K,
        "100000000", // powerPrecision
        matrix, // approximationMatrix
      ],
    ],
  );
  return balancerV2LpAggregator;
};

task("upgrade-polygon", "Upgrade contracts")
  .addOptionalParam("production", "run in production environment", false, types.boolean)
  .addOptionalParam("restartnonce", "propose transactions", false, types.boolean)
  .addOptionalParam("execute", "propose transactions", false, types.boolean)
  .addOptionalParam("keepversion", "keep the previous release published version. don't update it", false, types.boolean)
  .addOptionalParam("pause", "pause contract", false, types.boolean)
  .addOptionalParam("unpause", "unpause contract", false, types.boolean)
  .addOptionalParam("specific", "propose transactions", false, types.boolean)
  .addOptionalParam("poolfactory", "upgrade poolFactory", false, types.boolean)
  .addOptionalParam("assetfandler", "upgrade assetHandler", false, types.boolean)
  .addOptionalParam("poollogic", "upgrade poolLogic", false, types.boolean)
  .addOptionalParam("poolmanagerlogic", "upgrade poolManagerLogic", false, types.boolean)
  .addOptionalParam("poolperformance", "upgrade poolPerformance", false, types.boolean)
  .addOptionalParam("assets", "deploy new assets", false, types.boolean)
  .addOptionalParam("aavelendingpoolassetguard", "upgrade aaveLendingPoolAssetGuard", false, types.boolean)
  .addOptionalParam("sushilpassetguard", "upgrade sushiLPAssetGuard", false, types.boolean)
  .addOptionalParam("erc20guard", "upgrade erc20Guard", false, types.boolean)
  .addOptionalParam("lendingenabledassetguard", "upgrade LendingEnabledAssetGuard", false, types.boolean)
  .addOptionalParam("uniswapv2routerguard", "upgrade uniswapV2RouterGuard", false, types.boolean)
  .addOptionalParam("openassetguard", "upgrade openAssetGuard", false, types.boolean)
  .addOptionalParam("quicklpassetguard", "upgrade quickLPAssetGuard", false, types.boolean)
  .addOptionalParam("balancerv2guard", "upgrade balancerV2Guard", false, types.boolean)
  .addOptionalParam("balancermerkleorchardguard", "upgrade balancerMerkleOrchardGuard", false, types.boolean)
  .addOptionalParam("quickstakingrewardsguard", "upgrade quickStakingRewardsGuard", false, types.boolean)
  .addOptionalParam("sushiminichefv2guard", "upgrade sushiMiniChefV2Guard", false, types.boolean)
  .addOptionalParam("easyswapperguard", "upgrade easyswapperguard", false, types.boolean)
  .addOptionalParam("aaveincentivescontrollerguard", "upgrade AaveIncentivesControllerGuard", false, types.boolean)
  .addOptionalParam("aavelendingpoolguard", "upgrade AaveLendingPoolGuard", false, types.boolean)
  .addOptionalParam("oneinchv4guard", "upgrade oneInchV4Guard", false, types.boolean)
  .addOptionalParam("governancenames", "upgrade Governance contract address mapping", false, types.boolean)
  .addOptionalParam("univ3assetguard", "upgrade univ3assetguard", false, types.boolean)
  .addOptionalParam(
    "uniswapv3nonfungiblepositionguard",
    "upgrade uniswapv3nonfungiblepositionguard",
    false,
    types.boolean,
  )
  .setAction(async (taskArgs, hre) => {
    const ethers = hre.ethers;
    const upgrades = hre.upgrades;
    const provider = ethers.provider;
    const network = await ethers.provider.getNetwork();
    console.log("network:", network);
    if (network.chainId != 137) {
      throw new Error("Aborting: Expected chainId to 137. Must supply `--network polygon`");
    }

    if (taskArgs.restartnonce) {
      console.log("Restarting from last submitted nonce.");
    }

    await hre.run("compile");
    // Init tag
    const versionFile = taskArgs.production ? "versions" : "staging-versions";
    const versions = require(`../../publish/${network.name}/${versionFile}.json`);

    const ozPath = "./.openzeppelin/";
    const ozEnvFile = ozPath + (taskArgs.production ? "polygon-production.json" : "polygon-staging.json");
    const ozExpectedFile = ozPath + "unknown-137.json";
    fs.renameSync(ozEnvFile, ozExpectedFile);

    process.on("SIGINT", () => {
      console.log("Process Interrupted, Reverting rename");
      fs.renameSync(ozExpectedFile, ozEnvFile);
      console.log("Exiting...");
      // eventually exit
      process.exit(); // Add code if necessary
    });

    const writeVersions = () => {
      const data = JSON.stringify(versions, null, 2);
      fs.writeFileSync(`./publish/${network.name}/${versionFile}.json`, data);
    };

    const oldTag = Object.keys(versions)[Object.keys(versions).length - 1];
    let newTag: string;
    if (!taskArgs.specific || taskArgs.keepversion) {
      newTag = oldTag;
    } else {
      // update to latest release version
      newTag = await getTag();
    }
    console.log(`Old Version: ${oldTag}`);
    console.log(`New Version: ${newTag}`);
    // Comment this out as assets is default to true and it's always comes with pause/unpause true
    // const checkNewVersion = !taskArgs.assets && !taskArgs.pause && !taskArgs.unpause;
    // if (checkNewVersion && newTag == oldTag) throw "Error: No new version to upgrade"; // comment out as we could deploy and overrite the current version

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

    const writeNewGuards = () => {
      for (const newAssetGuard of newAssetGuards) {
        let replaced = false;
        for (const csvAssetGuard of csvAssetGuards) {
          if (newAssetGuard.GuardName == csvAssetGuard.GuardName) {
            csvAssetGuard.AssetType = newAssetGuard.AssetType;
            csvAssetGuard.GuardAddress = newAssetGuard.GuardAddress;
            csvAssetGuard.Description = newAssetGuard.Description;
            replaced = true;
            break;
          }
        }
        if (!replaced) {
          csvAssetGuards.push(newAssetGuard);
        }
      }
      if (csvAssetGuards.length > 0) writeCsv(csvAssetGuards, assetGuardfileName);

      for (const newContractGuard of newContractGuards) {
        let replaced = false;
        for (const csvContractGuard of csvContractGuards) {
          if (newContractGuard.ContractAddress.toLowerCase() == csvContractGuard.ContractAddress.toLowerCase()) {
            csvContractGuard.ContractAddress = newContractGuard.ContractAddress;
            csvContractGuard.GuardAddress = newContractGuard.GuardAddress;
            csvContractGuard.Description = newContractGuard.Description;
            replaced = true;
            break;
          }
        }
        if (!replaced) {
          csvContractGuards.push(newContractGuard);
        }
      }
      if (csvContractGuards.length > 0) writeCsv(csvContractGuards, contractGuardfileName);
      for (const newGovernanceName of newGovernanceNames) {
        let replaced = false;
        for (const csvGovernanceName of csvGovernanceNames) {
          if (newGovernanceName.Name == csvGovernanceName.Name) {
            csvGovernanceName.Destination = newGovernanceName.Destination;
            replaced = true;
            break;
          }
        }
        if (!replaced) {
          csvGovernanceNames.push(newGovernanceName);
        }
      }
      if (csvGovernanceNames.length > 0) writeCsv(csvGovernanceNames, governanceNamesfileName);
    };

    try {
      // Init contracts data
      const ProxyAdmin = await hre.artifacts.readArtifact("ProxyAdmin");
      const proxyAdmin = new ethers.utils.Interface(ProxyAdmin.abi);

      if (newTag != oldTag) {
        versions[newTag] = new Object();
      }
      versions[newTag].contracts = { ...versions[oldTag].contracts };
      versions[newTag].network = network;
      versions[newTag].date = new Date().toUTCString();
      let setLogic = false;
      let assetHandlerAssets = [];
      // Governance
      const Governance = await hre.artifacts.readArtifact("Governance");
      const governanceABI = new ethers.utils.Interface(Governance.abi);
      const governance = await ethers.getContractAt("Governance", versions[oldTag].contracts.Governance);

      // Pool Factory
      const poolFactoryProxy = versions[oldTag].contracts.PoolFactoryProxy;
      const PoolFactory = await hre.artifacts.readArtifact("PoolFactory");
      const PoolFactoryABI = new ethers.utils.Interface(PoolFactory.abi);
      const poolFactory = await ethers.getContractAt("PoolFactory", poolFactoryProxy);

      if (!taskArgs.specific || taskArgs.pause) {
        console.log("Will pause");
        if (taskArgs.execute) {
          const pauseABI = PoolFactoryABI.encodeFunctionData("pause", []);
          await proposeTx(poolFactoryProxy, pauseABI, "Pause Pool Factory", taskArgs.execute, taskArgs.restartnonce);
        }
      }
      if (!taskArgs.specific || taskArgs.assets) {
        // look up to check if csvAsset is in the current versions
        const fileName = taskArgs.production ? prodAssetFileName : stagingAssetFileName;
        const csvAssets = await csv().fromFile(fileName);

        // Check for any accidental duplicate addresses or price feeds in the CSV
        if (await hasDuplicates(csvAssets, "Address")) throw "Duplicate 'Address' field found in assets CSV";
        if (await hasDuplicates(csvAssets, "Chainlink Price Feed"))
          throw "Duplicate 'Chainlink Price Feed' field found in assets CSV";

        const SushiLPAggregator = await ethers.getContractFactory("UniV2LPAggregator");
        for (const csvAsset of csvAssets) {
          const foundInVersions = await checkAsset(
            csvAsset,
            versions[oldTag].contracts,
            poolFactory,
            assetHandlerAssets,
          );
          if (!foundInVersions) {
            const assetType = csvAsset.AssetType;
            switch (assetType) {
              case "2":
                console.log("Will deploy asset", csvAsset["Asset Name"]);
                if (!taskArgs.execute) {
                  break;
                }

                // Deploy Sushi LP Aggregator
                console.log("Deploying ", csvAsset["Asset Name"]);
                const sushiLPAggregator = await SushiLPAggregator.deploy(
                  csvAsset.Address,
                  versions[oldTag].contracts.PoolFactoryProxy,
                );
                await sushiLPAggregator.deployed();
                console.log(`${csvAsset["Asset Name"]} SushiLPAggregator deployed at ${sushiLPAggregator.address}`);
                assetHandlerAssets.push({
                  name: csvAsset["Asset Name"],
                  asset: csvAsset.Address,
                  assetType: assetType,
                  aggregator: sushiLPAggregator.address,
                  aggregatorName: csvAsset.aggregatorName,
                });
                break;
              case "3":
                console.log("Will deploy asset", csvAsset["Asset Name"]);
                if (!taskArgs.execute) {
                  break;
                }

                let usdPriceAggregatorAddress;
                if (!csvAsset["Chainlink Price Feed"]) {
                  // Deploy USDPriceAggregator
                  const USDPriceAggregator = await ethers.getContractFactory("USDPriceAggregator");
                  const usdPriceAggregator = await USDPriceAggregator.deploy();
                  await usdPriceAggregator.deployed();
                  usdPriceAggregatorAddress = usdPriceAggregator.address;
                } else {
                  // Use configured USDPriceAggregator
                  usdPriceAggregatorAddress = csvAsset["Chainlink Price Feed"];
                }

                console.log("USDPriceAggregator deployed at", usdPriceAggregatorAddress);
                assetHandlerAssets.push({
                  name: csvAsset["Asset Name"],
                  asset: csvAsset.Address,
                  assetType: assetType,
                  aggregator: usdPriceAggregatorAddress,
                  aggregatorName: csvAsset.aggregatorName,
                });
                break;
              default:
                console.log("Will deploy asset", csvAsset["Asset Name"]);
                if (!taskArgs.execute) {
                  break;
                }
                console.log(`Adding new asset to AssetHandler: ${csvAsset["Asset Name"]}`);
                const aggregator = await getAggregator(hre, csvAsset);
                assetHandlerAssets.push({
                  name: csvAsset["Asset Name"],
                  asset: csvAsset.Address,
                  assetType: assetType,
                  aggregator: aggregator,
                  aggregatorName: csvAsset.aggregatorName,
                });
            }
          }
        }

        const balancerLps = taskArgs.production ? prodBalancerConfig : stagingBalancerConfig;
        for (const balancerLp of balancerLps) {
          const foundInVersions = await checkBalancerLpAsset(
            balancerLp,
            versions[oldTag].contracts,
            poolFactory,
            assetHandlerAssets,
          );
          if (!foundInVersions) {
            console.log("Will deploy Balancer V2 LP asset", balancerLp.name);
            if (taskArgs.execute) {
              // Deploy Balancer LP Aggregator
              console.log("Deploying ", balancerLp.name);
              const balancerV2Aggregator = await deployBalancerV2LpAggregator(
                versions[oldTag].contracts.PoolFactoryProxy,
                balancerLp.data,
                hre,
              );
              console.log(`${balancerLp.name} BalancerV2LPAggregator deployed at ${balancerV2Aggregator.address}`);
              assetHandlerAssets.push({
                name: balancerLp.name,
                asset: balancerLp.data.pool,
                assetType: balancerLp.assetType,
                aggregator: balancerV2Aggregator.address,
                aggregatorName: "BalancerV2LPAggregator",
              });
            }
          }
        }

        const AssetHandlerLogic = await hre.artifacts.readArtifact("AssetHandler");
        const assetHandlerLogic = new ethers.utils.Interface(AssetHandlerLogic.abi);
        const addAssetsABI = assetHandlerLogic.encodeFunctionData("addAssets", [assetHandlerAssets]);

        if (assetHandlerAssets.length > 0) {
          await proposeTx(
            versions[oldTag].contracts.AssetHandlerProxy,
            addAssetsABI,
            "Update assets in Asset Handler",
            taskArgs.execute,
            taskArgs.restartnonce,
          );
          versions[newTag].contracts.Assets = [...versions[newTag].contracts.Assets, ...assetHandlerAssets];
        }
      }
      if (!taskArgs.specific || taskArgs.poolfactory) {
        console.log("Will upgrade poolfactory");
        if (taskArgs.execute) {
          const PoolFactoryContract = await ethers.getContractFactory("PoolFactory");
          const newPoolFactoryLogic = await upgrades.prepareUpgrade(poolFactoryProxy, PoolFactoryContract);
          console.log("New PoolFactory logic deployed to: ", newPoolFactoryLogic);
          const poolFactoryImpl = await ethers.getContractAt("PoolFactory", newPoolFactoryLogic);
          console.log("Initialising Impl");
          try {
            // If this script runs and then fails, on retry,
            // The deploy contract will already be initialised.
            await poolFactoryImpl.implInitializer();
          } catch (e: any) {
            if (!e.error.message.includes("contract is already initialized")) {
              throw e;
            }
          }

          await tryVerify(hre, newPoolFactoryLogic, "contracts/PoolFactory.sol:PoolFactory", []);

          const upgradeABI = proxyAdmin.encodeFunctionData("upgrade", [poolFactoryProxy, newPoolFactoryLogic]);
          await proposeTx(
            proxyAdminAddress,
            upgradeABI,
            "Upgrade Pool Factory",
            taskArgs.execute,
            taskArgs.restartnonce,
          );

          versions[newTag].contracts.PoolFactory = newPoolFactoryLogic;
        }
      }
      if (!taskArgs.specific || taskArgs.assethandler) {
        console.log("Will upgrade assethandler");
        if (taskArgs.execute) {
          let oldAssetHandler = versions[oldTag].contracts.AssetHandlerProxy;
          const AssetHandler = await ethers.getContractFactory("AssetHandler");
          const assetHandler = await upgrades.prepareUpgrade(oldAssetHandler, AssetHandler);
          console.log("assetHandler logic deployed to: ", assetHandler);

          await tryVerify(hre, assetHandler, "contracts/priceAggregators/AssetHandler.sol:AssetHandler", []);

          const upgradeABI = proxyAdmin.encodeFunctionData("upgrade", [oldAssetHandler, assetHandler]);
          await proposeTx(
            proxyAdminAddress,
            upgradeABI,
            "Upgrade Asset Handler",
            taskArgs.execute,
            taskArgs.restartnonce,
          );
        }
      }
      if (!taskArgs.specific || taskArgs.poollogic) {
        console.log("Will upgrade poollogic");
        if (taskArgs.execute) {
          let oldPooLogicProxy = versions[oldTag].contracts.PoolLogicProxy;
          const PoolLogic = await ethers.getContractFactory("PoolLogic");
          const poolLogic = await upgrades.prepareUpgrade(oldPooLogicProxy, PoolLogic);
          console.log("poolLogic deployed to: ", poolLogic);
          versions[newTag].contracts.PoolLogic = poolLogic;
          setLogic = true;

          await tryVerify(hre, poolLogic, "contracts/PoolLogic.sol:PoolLogic", []);
        }
      }
      if (!taskArgs.specific || taskArgs.poolmanagerlogic) {
        console.log("Will upgrade poolmanagerlogic");
        if (taskArgs.execute) {
          let oldPooManagerLogicProxy = versions[oldTag].contracts.PoolManagerLogicProxy;
          const PoolManagerLogic = await ethers.getContractFactory("PoolManagerLogic");
          const poolManagerLogic = await upgrades.prepareUpgrade(oldPooManagerLogicProxy, PoolManagerLogic);
          console.log("poolManagerLogic deployed to: ", poolManagerLogic);
          versions[newTag].contracts.PoolManagerLogic = poolManagerLogic;
          setLogic = true;

          await tryVerify(hre, poolManagerLogic, "contracts/PoolManagerLogic.sol:PoolManagerLogic", []);
        }
      }
      if (setLogic) {
        const setLogicABI = PoolFactoryABI.encodeFunctionData("setLogic", [
          versions[newTag].contracts.PoolLogic,
          versions[newTag].contracts.PoolManagerLogic,
        ]);
        await proposeTx(
          versions[oldTag].contracts.PoolFactoryProxy,
          setLogicABI,
          "Set logic for poolLogic and poolManagerLogic",
          taskArgs.execute,
        );
      }

      if (!taskArgs.specific || taskArgs.poolperformance) {
        console.log("Will upgrade poolperformance");
        if (versions[oldTag].contracts.PoolPerformanceProxy) {
          // Upgrade PoolPerformance
          if (taskArgs.execute) {
            let oldPoolPerformance = versions[oldTag].contracts.PoolPerformanceProxy;
            const PoolPerformance = await ethers.getContractFactory("PoolPerformance");
            const poolPerformance = await upgrades.prepareUpgrade(oldPoolPerformance, PoolPerformance);
            console.log("poolPerformance deployed to: ", poolPerformance);

            await tryVerify(hre, poolPerformance, "contracts/PoolPerformance.sol:PoolPerformance", []);

            const upgradeABI = proxyAdmin.encodeFunctionData("upgrade", [oldPoolPerformance, poolPerformance]);
            await proposeTx(
              proxyAdminAddress,
              upgradeABI,
              "Upgrade Pool Performance",
              taskArgs.execute,
              taskArgs.restartnonce,
            );

            versions[newTag].contracts.PoolPerformance = poolPerformance;
          }
        } else {
          if (taskArgs.execute) {
            // Deploy PoolPerformance (is not yet deployed)
            const PoolPerformance = await ethers.getContractFactory("PoolPerformance");
            const poolPerformanceProxy = await upgrades.deployProxy(PoolPerformance, []);
            await poolPerformanceProxy.deployed();
            console.log("poolPerformanceProxy deployed to:", poolPerformanceProxy.address);
            const poolPerformanceAddress = ethers.utils.hexValue(
              await provider.getStorageAt(poolPerformanceProxy.address, implementationStorage),
            );
            // const poolPerformanceAddress = await proxyAdmin.getProxyImplementation(poolPerformanceProxy.address);
            const poolPerformance = PoolPerformance.attach(poolPerformanceAddress);

            await poolPerformanceProxy.transferOwnership(protocolDao);

            await tryVerify(hre, poolPerformance.address, "contracts/PoolPerformance.sol:PoolPerformance", []);

            // Set PoolPerformance address in the Factory
            const setPoolPerformanceAddressABI = PoolFactoryABI.encodeFunctionData("setPoolPerformanceAddress", [
              poolPerformanceProxy.address,
            ]);
            await proposeTx(
              poolFactoryProxy,
              setPoolPerformanceAddressABI,
              `setPoolPerformanceAddress in Factory to ${poolPerformanceAddress}`,
              taskArgs.execute,
            );

            // Add to versions file
            versions[newTag].contracts.PoolPerformanceProxy = poolPerformanceProxy.address;
            versions[newTag].contracts.PoolPerformance = poolPerformanceAddress;
          }
        }
      }

      if (!taskArgs.specific || taskArgs.aavelendingpoolassetguard) {
        console.log("Will deploy aavelendingpoolassetguard");
        if (taskArgs.execute) {
          const AaveLendingPoolAssetGuard = await ethers.getContractFactory("AaveLendingPoolAssetGuard");
          const aaveLendingPoolAssetGuard = await AaveLendingPoolAssetGuard.deploy(aaveProtocolDataProvider);
          await aaveLendingPoolAssetGuard.deployed();
          console.log("AaveLendingPoolAssetGuard deployed at", aaveLendingPoolAssetGuard.address);
          versions[newTag].contracts.AaveLendingPoolAssetGuard = aaveLendingPoolAssetGuard.address;

          await tryVerify(
            hre,
            aaveLendingPoolAssetGuard.address,
            "contracts/guards/assetGuards/AaveLendingPoolAssetGuard.sol:AaveLendingPoolAssetGuard",
            [aaveProtocolDataProvider],
          );

          const setAssetGuardABI = governanceABI.encodeFunctionData("setAssetGuard", [
            3,
            aaveLendingPoolAssetGuard.address,
          ]);
          await proposeTx(
            versions[oldTag].contracts.Governance,
            setAssetGuardABI,
            "setAssetGuard for aaveLendingPoolAssetGuard",
            taskArgs.execute,
          );
          newAssetGuards.push({
            AssetType: 3,
            GuardName: "AaveLendingPoolAssetGuard",
            GuardAddress: aaveLendingPoolAssetGuard.address,
            Description: "Aave Lending Pool",
          });
        }
      }
      if (!taskArgs.specific || taskArgs.sushilpassetguard) {
        console.log("Will deploy sushilpassetguard");
        if (taskArgs.execute) {
          const SushiLPAssetGuard = await ethers.getContractFactory("SushiLPAssetGuard");
          const sushiLPAssetGuard = await SushiLPAssetGuard.deploy(sushiMiniChefV2); // initialise with Sushi staking pool Id
          await sushiLPAssetGuard.deployed();
          console.log("SushiLPAssetGuard deployed at", sushiLPAssetGuard.address);
          versions[newTag].contracts.SushiLPAssetGuard = sushiLPAssetGuard.address;

          await tryVerify(
            hre,
            sushiLPAssetGuard.address,
            "contracts/guards/assetGuards/SushiLPAssetGuard.sol:SushiLPAssetGuard",
            [sushiMiniChefV2],
          );

          await sushiLPAssetGuard.transferOwnership(protocolDao);
          const setAssetGuardABI = governanceABI.encodeFunctionData("setAssetGuard", [2, sushiLPAssetGuard.address]);
          await proposeTx(
            versions[oldTag].contracts.Governance,
            setAssetGuardABI,
            "setAssetGuard for SushiLPAssetGuard",
            taskArgs.execute,
          );
          newAssetGuards.push({
            AssetType: 2,
            GuardName: "SushiLPAssetGuard",
            GuardAddress: sushiLPAssetGuard.address,
            Description: "Sushi LP tokens",
          });
        }
      }
      if (!taskArgs.specific || taskArgs.erc20guard) {
        console.log("Will deploy erc20guard");
        if (taskArgs.execute) {
          const ERC20Guard = await ethers.getContractFactory("ERC20Guard");
          const erc20Guard = await ERC20Guard.deploy();
          await erc20Guard.deployed();
          console.log("ERC20Guard deployed at", erc20Guard.address);
          versions[newTag].contracts.ERC20Guard = erc20Guard.address;

          await tryVerify(hre, erc20Guard.address, "contracts/guards/assetGuards/ERC20Guard.sol:ERC20Guard", []);

          const setAssetGuardABI = governanceABI.encodeFunctionData("setAssetGuard", [0, erc20Guard.address]);
          await proposeTx(
            versions[oldTag].contracts.Governance,
            setAssetGuardABI,
            "setAssetGuard for ERC20Guard",
            taskArgs.execute,
            taskArgs.restartnonce,
          );
          newAssetGuards.push({
            AssetType: 0,
            GuardName: "ERC20Guard",
            GuardAddress: erc20Guard.address,
            Description: "ERC20 tokens",
          });
        }
      }
      if (!taskArgs.specific || taskArgs.lendingenabledassetguard) {
        console.log("Will deploy lendingenabledassetguard");
        if (taskArgs.execute) {
          const LendingEnabledAssetGuard = await ethers.getContractFactory("LendingEnabledAssetGuard");
          const lendingEnabledAssetGuard = await LendingEnabledAssetGuard.deploy();
          await lendingEnabledAssetGuard.deployed();
          console.log("LendingEnabledAssetGuard deployed at", lendingEnabledAssetGuard.address);

          versions[newTag].contracts.LendingEnabledAssetGuard = lendingEnabledAssetGuard.address;

          await tryVerify(
            hre,
            lendingEnabledAssetGuard.address,
            "contracts/guards/assetGuards/LendingEnabledAssetGuard.sol:LendingEnabledAssetGuard",
            [],
          );

          const setAssetGuardABI = governanceABI.encodeFunctionData("setAssetGuard", [
            4,
            lendingEnabledAssetGuard.address,
          ]);
          await proposeTx(
            versions[oldTag].contracts.Governance,
            setAssetGuardABI,
            "setAssetGuard for LendingEnabledAssetGuard",
            taskArgs.execute,
          );
          newAssetGuards.push({
            AssetType: 4,
            GuardName: "LendingEnabledAssetGuard",
            GuardAddress: lendingEnabledAssetGuard.address,
            Description: "Lending Enabled Asset tokens",
          });
        }
      }
      if (!taskArgs.specific || taskArgs.uniswapv2routerguard) {
        console.log("Will deploy uniswapv2routerguard");
        if (taskArgs.execute) {
          const UniswapV2RouterGuard = await ethers.getContractFactory("UniswapV2RouterGuard");
          const uniswapV2RouterGuard = await UniswapV2RouterGuard.deploy(10, 100); // set slippage 10%
          await uniswapV2RouterGuard.deployed();
          console.log("UniswapV2RouterGuard deployed at", uniswapV2RouterGuard.address);
          versions[newTag].contracts.UniswapV2RouterGuard = uniswapV2RouterGuard.address;

          await tryVerify(
            hre,
            uniswapV2RouterGuard.address,
            "contracts/guards/contractGuards/UniswapV2RouterGuard.sol:UniswapV2RouterGuard",
            [10, 100],
          );

          await uniswapV2RouterGuard.transferOwnership(protocolDao);
          let setContractGuardABI = governanceABI.encodeFunctionData("setContractGuard", [
            sushiswapV2Router,
            uniswapV2RouterGuard.address,
          ]);
          await proposeTx(
            versions[oldTag].contracts.Governance,
            setContractGuardABI,
            "setContractGuard for sushiswapV2Router",
            taskArgs.execute,
          );
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
          await proposeTx(
            versions[oldTag].contracts.Governance,
            setContractGuardABI,
            "setContractGuard for quickswapRouter",
            taskArgs.execute,
          );
          newContractGuards.push({
            ContractAddress: quickswapRouter,
            GuardName: "UniswapV2RouterGuard",
            GuardAddress: uniswapV2RouterGuard.address,
            Description: "Quickswap V2 router",
          });
        }
      }
      if (!taskArgs.specific || taskArgs.balancerv2guard) {
        console.log("Will deploy balancerv2guard");
        if (taskArgs.execute) {
          const BalancerV2Guard = await ethers.getContractFactory("BalancerV2Guard");
          const balancerV2Guard = await BalancerV2Guard.deploy(10, 100); // set slippage 10%
          await balancerV2Guard.deployed();
          console.log("BalancerV2Guard deployed at", balancerV2Guard.address);
          versions[newTag].contracts.BalancerV2Guard = balancerV2Guard.address;

          await tryVerify(
            hre,
            balancerV2Guard.address,
            "contracts/guards/contractGuards/BalancerV2Guard.sol:BalancerV2Guard",
            [10, 100],
          );

          await balancerV2Guard.transferOwnership(protocolDao);
          let setContractGuardABI = governanceABI.encodeFunctionData("setContractGuard", [
            balancerV2Vault,
            balancerV2Guard.address,
          ]);
          await proposeTx(
            versions[oldTag].contracts.Governance,
            setContractGuardABI,
            "setContractGuard for balancerV2Vault",
            taskArgs.execute,
          );
          newContractGuards.push({
            ContractAddress: balancerV2Vault,
            GuardName: "BalancerV2Guard",
            GuardAddress: balancerV2Guard.address,
            Description: "Balancer V2 Guard",
          });
        }
      }
      if (!taskArgs.specific || taskArgs.balancermerkleorchardguard) {
        console.log("Will deploy balancermerkleorchardguard");
        if (taskArgs.execute) {
          const BalancerMerkleOrchardGuard = await ethers.getContractFactory("BalancerMerkleOrchardGuard");
          const balancerMerkleOrchardGuard = await BalancerMerkleOrchardGuard.deploy();
          await balancerMerkleOrchardGuard.deployed();
          console.log("BalancerMerkleOrchardGuard deployed at", balancerMerkleOrchardGuard.address);
          versions[newTag].contracts.BalancerMerkleOrchardGuard = balancerMerkleOrchardGuard.address;

          await tryVerify(
            hre,
            balancerMerkleOrchardGuard.address,
            "contracts/guards/contractGuards/BalancerMerkleOrchardGuard.sol:BalancerMerkleOrchardGuard",
            [],
          );

          let setContractGuardABI = governanceABI.encodeFunctionData("setContractGuard", [
            balancerMerkleOrchard,
            balancerMerkleOrchardGuard.address,
          ]);
          await proposeTx(
            versions[oldTag].contracts.Governance,
            setContractGuardABI,
            "setContractGuard for balancerMerkleOrchard",
            taskArgs.execute,
          );
          newContractGuards.push({
            ContractAddress: balancerMerkleOrchard,
            GuardName: "BalancerMerkleOrchardGuard",
            GuardAddress: balancerMerkleOrchardGuard.address,
            Description: "Balancer Merkle Orchard Guard",
          });
        }
      }
      if (!taskArgs.specific || taskArgs.openassetguard) {
        console.log("Will deploy openassetguard");
        if (taskArgs.execute) {
          const fileName = taskArgs.production ? prodExternalAssetFileName : stagingExternalAssetFileName;
          const csvAssets = await csv().fromFile(fileName);
          let addresses = csvAssets.map((asset: any) => asset.Address);
          const OpenAssetGuard = await ethers.getContractFactory("OpenAssetGuard");
          const openAssetGuard = await OpenAssetGuard.deploy(addresses);
          await openAssetGuard.deployed();
          console.log("OpenAssetGuard deployed at", openAssetGuard.address);
          versions[newTag].contracts.OpenAssetGuard = openAssetGuard.address;

          await tryVerify(
            hre,
            openAssetGuard.address,
            "contracts/guards/assetGuards/OpenAssetGuard.sol:OpenAssetGuard",
            [addresses],
          );

          await openAssetGuard.transferOwnership(protocolDao);
          const setAddressesABI = governanceABI.encodeFunctionData("setAddresses", [
            [[ethers.utils.formatBytes32String("openAssetGuard"), openAssetGuard.address]],
          ]);
          await proposeTx(
            versions[oldTag].contracts.Governance,
            setAddressesABI,
            "setAddresses for openAssetGuard",
            taskArgs.execute,
            taskArgs.restartnonce,
          );
          newGovernanceNames.push({
            Name: "openAssetGuard",
            Destination: openAssetGuard.address,
          });
        }
      }
      if (!taskArgs.specific || taskArgs.quicklpassetguard) {
        console.log("Will deploy quicklpassetguard");
        if (taskArgs.execute) {
          const QuickLPAssetGuard = await ethers.getContractFactory("QuickLPAssetGuard");
          const quickLPAssetGuard = await QuickLPAssetGuard.deploy(quickStakingRewardsFactory);
          await quickLPAssetGuard.deployed();
          console.log("quickLPAssetGuard deployed at", quickLPAssetGuard.address);
          versions[newTag].contracts.QuickLPAssetGuard = quickLPAssetGuard.address;

          await tryVerify(
            hre,
            quickLPAssetGuard.address,
            "contracts/guards/assetGuards/QuickLPAssetGuard.sol:QuickLPAssetGuard",
            [quickStakingRewardsFactory],
          );

          await quickLPAssetGuard.transferOwnership(protocolDao);
          const setAssetGuardABI = governanceABI.encodeFunctionData("setAssetGuard", [5, quickLPAssetGuard.address]);
          await proposeTx(
            versions[oldTag].contracts.Governance,
            setAssetGuardABI,
            "setAssetGuard for quickLPAssetGuard",
            taskArgs.execute,
          );
          newAssetGuards.push({
            AssetType: 5,
            GuardName: "QuickLPAssetGuard",
            GuardAddress: quickLPAssetGuard.address,
            Description: "Quick LP tokens",
          });
        }
      }
      if (!taskArgs.specific || taskArgs.quickstakingrewardsguard) {
        console.log("Will deploy quickstakingrewardsguard");
        if (taskArgs.execute) {
          const QuickStakingRewardsGuard = await ethers.getContractFactory("QuickStakingRewardsGuard");
          const quickStakingRewardsGuard = await QuickStakingRewardsGuard.deploy();
          await quickStakingRewardsGuard.deployed();
          console.log("quickStakingRewardsGuard deployed at", quickStakingRewardsGuard.address);
          versions[newTag].contracts.QuickStakingRewardsGuard = quickStakingRewardsGuard.address;

          await tryVerify(
            hre,
            quickStakingRewardsGuard.address,
            "contracts/guards/contractGuards/QuickStakingRewardsGuard.sol:QuickStakingRewardsGuard",
            [],
          );

          const setContractGuardABI = governanceABI.encodeFunctionData("setContractGuard", [
            quickLpUsdcWethStakingRewards,
            quickStakingRewardsGuard.address,
          ]);
          await proposeTx(
            versions[oldTag].contracts.Governance,
            setContractGuardABI,
            "setContractGuard for QuickStakingRewardsGuard",
            taskArgs.execute,
          );
          newContractGuards.push({
            ContractAddress: quickLpUsdcWethStakingRewards,
            GuardName: "QuickStakingRewardsGuard",
            GuardAddress: quickStakingRewardsGuard.address,
            Description: "Quick Staking Reward",
          });
        }
      }
      if (!taskArgs.specific || taskArgs.sushiminichefv2guard) {
        console.log("Will deploy sushiminichefv2guard");
        if (taskArgs.execute) {
          const SushiMiniChefV2Guard = await ethers.getContractFactory("SushiMiniChefV2Guard");
          const sushiMiniChefV2Guard = await SushiMiniChefV2Guard.deploy([sushiToken, wmatic]);
          await sushiMiniChefV2Guard.deployed();
          console.log("SushiMiniChefV2Guard deployed at", sushiMiniChefV2Guard.address);
          versions[newTag].contracts.SushiMiniChefV2Guard = sushiMiniChefV2Guard.address;

          await tryVerify(
            hre,
            sushiMiniChefV2Guard.address,
            "contracts/guards/contractGuards/SushiMiniChefV2Guard.sol:SushiMiniChefV2Guard",
            [[sushiToken, wmatic]],
          );

          const setContractGuardABI = governanceABI.encodeFunctionData("setContractGuard", [
            sushiMiniChefV2,
            sushiMiniChefV2Guard.address,
          ]);
          await proposeTx(
            versions[oldTag].contracts.Governance,
            setContractGuardABI,
            "setContractGuard for sushiMiniChefV2Guard",
            taskArgs.execute,
          );
          newContractGuards.push({
            ContractAddress: sushiMiniChefV2,
            GuardName: "SushiMiniChefV2Guard",
            GuardAddress: sushiMiniChefV2Guard.address,
            Description: "Sushi rewards contract",
          });
        }
      }
      if (!taskArgs.specific || taskArgs.easyswapperguard) {
        console.log("Will deploy easyswapperguard");
        if (taskArgs.execute) {
          const EasySwapperGuard = await ethers.getContractFactory("EasySwapperGuard");
          const easySwapperGuard = await EasySwapperGuard.deploy();
          await easySwapperGuard.deployed();
          console.log("EasySwapperGuard deployed at", easySwapperGuard.address);
          versions[newTag].contracts.EasySwapperGuard = easySwapperGuard.address;

          await tryVerify(hre, easySwapperGuard.address, "contracts/guards/EasySwapperGuard.sol:EasySwapperGuard", []);

          const setContractGuardABI = governanceABI.encodeFunctionData("setContractGuard", [
            dhedgeEasySwapperAddress,
            easySwapperGuard.address,
          ]);
          await proposeTx(
            versions[oldTag].contracts.Governance,
            setContractGuardABI,
            "setContractGuard for easySwapperGuard",
            taskArgs.execute,
          );
          newContractGuards.push({
            ContractAddress: dhedgeEasySwapperAddress,
            GuardName: "EasySwapperGuard",
            GuardAddress: easySwapperGuard.address,
            Description: "Dhedge EasySwapper - allows access to toros pools",
          });
        }
      }
      if (!taskArgs.specific || taskArgs.aaveincentivescontrollerguard) {
        console.log("Will deploy aaveincentivescontrollerguard");
        if (taskArgs.execute) {
          const AaveIncentivesControllerGuard = await ethers.getContractFactory("AaveIncentivesControllerGuard");
          console.log("wmatic: ", wmatic);
          const aaveIncentivesControllerGuard = await AaveIncentivesControllerGuard.deploy(wmatic);
          await aaveIncentivesControllerGuard.deployed();
          console.log("AaveIncentivesControllerGuard deployed at", aaveIncentivesControllerGuard.address);
          versions[newTag].contracts.AaveIncentivesControllerGuard = aaveIncentivesControllerGuard.address;

          await tryVerify(
            hre,
            aaveIncentivesControllerGuard.address,
            "contracts/guards/contractGuards/AaveIncentivesControllerGuard.sol:AaveIncentivesControllerGuard",
            [wmatic],
          );

          const setContractGuardABI = governanceABI.encodeFunctionData("setContractGuard", [
            aaveIncentivesController,
            aaveIncentivesControllerGuard.address,
          ]);
          await proposeTx(
            versions[oldTag].contracts.Governance,
            setContractGuardABI,
            "setContractGuard for AaveIncentivesControllerGuard",
            taskArgs.execute,
          );
          newContractGuards.push({
            ContractAddress: aaveIncentivesController,
            GuardName: "AaveIncentivesControllerGuard",
            GuardAddress: aaveIncentivesControllerGuard.address,
            Description: "Aave Incentives Controller contract",
          });
        }
      }
      if (!taskArgs.specific || taskArgs.aavelendingpoolguard) {
        console.log("Will deploy aavelendingpoolguard");
        if (taskArgs.execute) {
          const AaveLendingPoolGuard = await ethers.getContractFactory("AaveLendingPoolGuard");
          const aaveLendingPoolGuard = await AaveLendingPoolGuard.deploy();
          await aaveLendingPoolGuard.deployed();
          console.log("AaveLendingPoolGuard deployed at", aaveLendingPoolGuard.address);
          versions[newTag].contracts.AaveLendingPoolGuard = aaveLendingPoolGuard.address;

          await tryVerify(
            hre,
            aaveLendingPoolGuard.address,
            "contracts/guards/contractGuards/AaveLendingPoolGuard.sol:AaveLendingPoolGuard",
            [],
          );

          const setContractGuardABI = governanceABI.encodeFunctionData("setContractGuard", [
            aaveLendingPool,
            aaveLendingPoolGuard.address,
          ]);
          await proposeTx(
            versions[oldTag].contracts.Governance,
            setContractGuardABI,
            "setContractGuard for aaveLendingPoolGuard",
            taskArgs.execute,
          );
          newContractGuards.push({
            ContractAddress: aaveLendingPool,
            GuardName: "AaveLendingPoolGuard",
            GuardAddress: aaveLendingPoolGuard.address,
            Description: "Aave Lending Pool contract",
          });
        }
      }
      if (!taskArgs.specific || taskArgs.oneinchv4guard) {
        console.log("Will deploy oneinchv4guard");
        if (taskArgs.execute) {
          const OneInchV3Guard = await ethers.getContractFactory("OneInchV3Guard");
          const oneInchV4Guard = await OneInchV3Guard.deploy(10, 100); // set slippage 10%
          await oneInchV4Guard.deployed();
          console.log("oneInchV4Guard deployed at", oneInchV4Guard.address);
          versions[newTag].contracts.OneInchV4Guard = oneInchV4Guard.address;

          await tryVerify(
            hre,
            oneInchV4Guard.address,
            "contracts/guards/contractGuards/OneInchV3Guard.sol:OneInchV3Guard",
            [10, 100],
          );

          const setContractGuardABI = governanceABI.encodeFunctionData("setContractGuard", [
            oneInchV4Router,
            oneInchV4Guard.address,
          ]);
          await proposeTx(
            versions[oldTag].contracts.Governance,
            setContractGuardABI,
            "setContractGuard for oneInchV4Guard",
            taskArgs.execute,
          );
          newContractGuards.push({
            ContractAddress: oneInchV4Router,
            GuardName: "OneInchV4Guard",
            GuardAddress: oneInchV4Guard.address,
            Description: "OneInch V4 Router",
          });
        }
      }

      if (!taskArgs.specific || taskArgs.governancenames) {
        console.log("Will deploy governancenames");
        for (const csvGovernanceName of csvGovernanceNames) {
          const name = csvGovernanceName.Name;
          const destination = csvGovernanceName.Destination;
          const nameBytes = ethers.utils.formatBytes32String(name);
          const configuredDestination = await governance.nameToDestination(nameBytes);

          if (configuredDestination === "0x0000000000000000000000000000000000000000") {
            const setAddressesABI = governanceABI.encodeFunctionData("setAddresses", [[[nameBytes, destination]]]);
            await proposeTx(
              versions[oldTag].contracts.Governance,
              setAddressesABI,
              `setAddresses for ${name} to ${destination}`,
              taskArgs.execute,
            );
          }
        }
      }

      if (!taskArgs.specific || taskArgs.unpause) {
        console.log("Will unpause");
        if (taskArgs.execute) {
          // Unpause Pool Factory
          const unpauseABI = PoolFactoryABI.encodeFunctionData("unpause", []);
          await proposeTx(
            poolFactoryProxy,
            unpauseABI,
            "Unpause pool Factory",
            taskArgs.execute,
            taskArgs.restartnonce,
          );
        }
      }

      if (!taskArgs.specific || taskArgs.univ3assetguard) {
        console.log("Will deploy univ3assetguard");
        if (taskArgs.execute) {
          const UniswapV3AssetGuard = await ethers.getContractFactory("UniswapV3AssetGuard");
          const uniV3AssetGuard = await UniswapV3AssetGuard.deploy(uniswapV3.nonfungiblePositionManager);
          await uniV3AssetGuard.deployed();
          console.log("UniswapV3AssetGuard deployed at", uniV3AssetGuard.address);

          versions[newTag].contracts.UniswapV3AssetGuard = uniV3AssetGuard.address;

          await tryVerify(
            hre,
            uniV3AssetGuard.address,
            "contracts/guards/assetGuards/UniswapV3AssetGuard.sol:UniswapV3AssetGuard",
            [],
          );

          const setAssetGuardABI = governanceABI.encodeFunctionData("setAssetGuard", [7, uniV3AssetGuard.address]);
          await proposeTx(
            versions[oldTag].contracts.Governance,
            setAssetGuardABI,
            "setAssetGuard for UniswapV3AssetGuard",
            taskArgs.execute,
          );
          newAssetGuards.push({
            AssetType: 7,
            GuardName: "UniswapV3AssetGuard",
            GuardAddress: uniV3AssetGuard.address,
            Description: "Uniswap V3 Asset tokens",
          });
        }
      }
      if (!taskArgs.specific || taskArgs.uniswapv3nonfungiblepositionguard) {
        console.log("Will deploy uniswapv3nonfungiblepositionguard");
        if (taskArgs.execute) {
          const UniswapV3NonfungiblePositionGuard = await ethers.getContractFactory(
            "UniswapV3NonfungiblePositionGuard",
          );
          const uniswapV3NonfungiblePositionGuard = await UniswapV3NonfungiblePositionGuard.deploy(
            uniswapV3.nonfungiblePositionManager,
            1,
          );
          await uniswapV3NonfungiblePositionGuard.deployed();
          console.log("UniswapV3NonfungiblePositionGuard deployed at", uniswapV3NonfungiblePositionGuard.address);
          versions[newTag].contracts.UniswapV3NonfungiblePositionGuard = uniswapV3NonfungiblePositionGuard.address;

          await tryVerify(
            hre,
            uniswapV3NonfungiblePositionGuard.address,
            "contracts/guards/contractGuards/uniswapV3/UniswapV3NonfungiblePositionGuard.sol:UniswapV3NonfungiblePositionGuard",
            [],
          );

          const setContractGuardABI = governanceABI.encodeFunctionData("setContractGuard", [
            uniswapV3.nonfungiblePositionManager,
            uniswapV3NonfungiblePositionGuard.address,
          ]);
          await proposeTx(
            versions[oldTag].contracts.Governance,
            setContractGuardABI,
            "setContractGuard for uniswapV3NonfungiblePositionGuard",
            taskArgs.execute,
          );
          newContractGuards.push({
            ContractAddress: uniswapV3.nonfungiblePositionManager,
            GuardName: "UniswapV3NonfungiblePositionGuard",
            GuardAddress: uniswapV3NonfungiblePositionGuard.address,
            Description: "Uniswap V3 Nonfungible Position contract",
          });
        }
      }
    } catch (e) {
      console.error(e);
      console.log("UPGRADE EXIT UNEXPECTED");
    } finally {
      if (taskArgs.execute) {
        // only update the files if executing an upgrade
        console.log("Updating versions.json");
        writeVersions();
        console.log("Updating csv");
        writeNewGuards();
        console.log(nonceLog);
      }

      console.log("Switching back OZ file");
      fs.renameSync(ozExpectedFile, ozEnvFile);
    }
  });

module.exports = {};
