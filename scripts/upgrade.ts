import { task, types } from "hardhat/config";
import { HardhatRuntimeEnvironment } from "hardhat/types";

import fs from "fs";

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
} from "./Helpers";
import { dhedgeEasySwapperAddress } from "../config/chainData/polygon-data";
import { string } from "hardhat/internal/core/params/argumentTypes";

const Decimal = require("decimal.js");

const implementationStorage = "0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc";

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
  .setAction(async (taskArgs, hre) => {
    const ethers = hre.ethers;
    const upgrades = hre.upgrades;
    const provider = ethers.provider;
    const network = await ethers.provider.getNetwork();

    const addresses: IAddresses = {};

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
    };

    try {
      // Init contracts data
      const ProxyAdmin = await hre.artifacts.readArtifact("ProxyAdmin");

      if (newTag != oldTag) {
        versions[newTag] = new Object();
      }
      versions[newTag].contracts = { ...versions[oldTag].contracts };
      versions[newTag].network = network;
      versions[newTag].date = new Date().toUTCString();
      let setLogic = false;

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
      }
      if (!taskArgs.specific || taskArgs.poolfactory) {
      }
      if (!taskArgs.specific || taskArgs.assethandler) {
      }

      if (!taskArgs.specific || taskArgs.poollogic) {
      }
      if (!taskArgs.specific || taskArgs.poolmanagerlogic) {
      }

      if (!taskArgs.specific || taskArgs.poolperformance) {
      }

      // Asset Guards
      if (!taskArgs.specific || taskArgs.aavelendingpoolassetguard) {
      }
      if (!taskArgs.specific || taskArgs.sushilpassetguard) {
      }
      if (!taskArgs.specific || taskArgs.erc20guard) {
      }
      if (!taskArgs.specific || taskArgs.lendingenabledassetguard) {
      }
      if (!taskArgs.specific || taskArgs.quicklpassetguard) {
      }

      // Contract Guards
      if (!taskArgs.specific || taskArgs.uniswapv2routerguard) {
      }
      if (!taskArgs.specific || taskArgs.balancerv2guard) {
      }
      if (!taskArgs.specific || taskArgs.balancermerkleorchardguard) {
      }

      // Other Weird Guards
      if (!taskArgs.specific || taskArgs.openassetguard) {
      }

      if (!taskArgs.specific || taskArgs.quickstakingrewardsguard) {
      }
      if (!taskArgs.specific || taskArgs.sushiminichefv2guard) {
      }
      if (!taskArgs.specific || taskArgs.easyswapperguard) {
      }
      if (!taskArgs.specific || taskArgs.aaveincentivescontrollerguard) {
      }
      if (!taskArgs.specific || taskArgs.aavelendingpoolguard) {
      }
      if (!taskArgs.specific || taskArgs.oneinchv4guard) {
      }

      // Governance
      if (!taskArgs.specific || taskArgs.governancenames) {
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
