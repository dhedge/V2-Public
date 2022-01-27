import fs from "fs";
import { task, types } from "hardhat/config";
import { getTag, nonceLog } from "../Helpers";
import { getDeploymentData } from "./deploymentData";
import { IJob } from "./types";

import { pauseJob } from "./jobs/pauseJob";
import { assetsJob } from "./jobs/assetsJob";
import { poolFactoryJob } from "./jobs/poolFactoryJob";
import { assetHandlerJob } from "./jobs/assetHandlerJob";
import { poolLogicJob } from "./jobs/poolLogicJob";
import { poolPerformanceJob } from "./jobs/poolPerformanceJobs";
import { aaveLendingPoolContractGuardJob } from "./jobs/contractGuards/aaveLendingPoolContractGuardJob";
import { sushiLpAssetGuardJob } from "./jobs/assetGuards/sushiLpAssetGuardJob";
import { poolManagerLogicJob } from "./jobs/poolManagerLogicJob";
import { erc20AssetGuardJob } from "./jobs/assetGuards/erc20AssetGuardJob";

import { quickLpAssetGuardJob } from "./jobs/assetGuards/quickLpAssetGuardJob";
import { v2RouterContractGuardJob } from "./jobs/contractGuards/v2RouterContractGuardJob";
import { balancerv2ContractGuard } from "./jobs/contractGuards/balancerv2ContractGuardJob";
import { balancerMerkleOrchardContractGuardJob } from "./jobs/contractGuards/balancerMerkleOrchardContractGuardJob";
import { openAssetContractGuardJob } from "./jobs/otherWeirdGuards/openAssetContractGuardJob";
import { quickStakingRewardsContractGuardJob } from "./jobs/contractGuards/quickStakingRewardsContractGuardJob";
import { sushiMiniChefV2GuardGuardJob } from "./jobs/contractGuards/sushiMiniChefV2GuardGuardJob";
import { easySwapperContractGuardJob } from "./jobs/contractGuards/easySwapperContractGuardJob";
import { aaveIncentivesControllerContractGuardJob } from "./jobs/contractGuards/aaveIncentivesControllerContractGuardJob";
import { oneInchV4ContractGuardJob } from "./jobs/contractGuards/oneInchV4ContractGuardJob";
import { governanceNamesJob } from "./jobs/governanceNamesJob";
import { unpauseJob } from "./jobs/unpauseJob";
import { lendingEnabledAssetGuardJob } from "./jobs/assetGuards/lendingEnabledAssetGuardJob";

const jobs: { [key: string]: IJob<void> } = {
  pause: pauseJob,
  unpause: unpauseJob,

  assets: assetsJob,
  assethandler: assetHandlerJob,

  poolfactory: poolFactoryJob,
  poollogic: poolLogicJob,
  poolmanagerlogic: poolManagerLogicJob,

  poolperformance: poolPerformanceJob,

  // Asset Guards
  aavelendingpoolassetguard: aaveLendingPoolContractGuardJob,
  sushilpassetguard: sushiLpAssetGuardJob,
  erc20guard: erc20AssetGuardJob,
  lendingenabledassetguard: lendingEnabledAssetGuardJob,
  quicklpassetguard: quickLpAssetGuardJob,

  // Contract Guards
  uniswapv2routerguard: v2RouterContractGuardJob,
  balancerv2guard: balancerv2ContractGuard,
  balancermerkleorchardguard: balancerMerkleOrchardContractGuardJob,
  quickstakingrewardsguard: quickStakingRewardsContractGuardJob,
  sushiminichefv2guard: sushiMiniChefV2GuardGuardJob,
  easyswapperguard: easySwapperContractGuardJob,
  aaveincentivescontrollerguard: aaveIncentivesControllerContractGuardJob,
  aavelendingpoolguard: aaveLendingPoolContractGuardJob,
  oneinchv4guard: oneInchV4ContractGuardJob,

  // Other Weird Guards
  openassetguard: openAssetContractGuardJob,

  // Governance
  governancenames: governanceNamesJob,
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
  .setAction(async (taskArgs, hre) => {
    const ethers = hre.ethers;
    const network = await ethers.provider.getNetwork();

    const { addresses, filenames, versionsFileName } = getDeploymentData(
      network.chainId,
      taskArgs.production ? "production" : "staging",
    );

    console.log("network:", network);
    if (![137, 10].includes(network.chainId)) {
      throw new Error("Aborting: Expected chainId to 137|10. Must supply `--network polygon|optimism`");
    }

    if (taskArgs.restartnonce) {
      console.log("Restarting from last submitted nonce.");
    }

    await hre.run("compile");
    const versions = require(versionsFileName);

    const writeVersions = () => {
      const data = JSON.stringify(versions, null, 2);
      fs.writeFileSync(versionsFileName, data);
    };

    // TODO: This code needs to be reviewed and refactored
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

    if (newTag != oldTag) {
      versions[newTag] = new Object();
    }
    versions[newTag].contracts = { ...versions[oldTag].contracts };
    versions[newTag].network = network;
    versions[newTag].date = new Date().toUTCString();

    // TODO: ^^This code needs to be reviewed and refactored

    try {
      await Promise.all(
        Object.keys(jobs)
          .filter((key) => {
            return !taskArgs.specific || taskArgs[key];
          })
          .map((key) => jobs[key](taskArgs, hre, versions, filenames, addresses)),
      );
    } catch (e) {
      console.error(e);
      console.log("UPGRADE EXIT UNEXPECTED");
    } finally {
      // TODO: ^^This code needs to be reviewed and refactored
      if (taskArgs.execute) {
        // only update the files if executing an upgrade
        console.log("Updating versions.json");
        // TODO:
        writeVersions();
        console.log("Updating csv");
        // TODO: Shouldn't be using a mutable export/import to pass out this data
        console.log(nonceLog);
      }
    }
  });
