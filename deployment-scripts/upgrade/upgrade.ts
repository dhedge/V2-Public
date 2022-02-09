import fs from "fs";
import { task, types } from "hardhat/config";
import { getTag, nonceLog } from "../Helpers";
import { getDeploymentData } from "./getDeploymentData";
import { IJob, IVersions } from "../types";

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

  // Upgradable
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

  // has to be last
  unpause: unpauseJob,
};

const upgradeTask = task("upgrade", "Upgrade contracts")
  .addParam("production", "run in production environment", false, types.boolean)
  .addParam("restartnonce", "propose transactions", false, types.boolean)
  .addParam("execute", "propose transactions", false, types.boolean)
  .addParam("specific", "run only specified tasks", false, types.boolean)
  .addOptionalParam(
    "keepversion",
    "keep the previous release published version. don't update it",
    false,
    types.boolean,
  );

Object.keys(jobs).forEach((job) => {
  // We make each job a taskArg for hardhat :)
  upgradeTask.addOptionalParam(job, "run " + job, false, types.boolean);
});

upgradeTask.setAction(async (taskArgs, hre) => {
  const ethers = hre.ethers;
  const network = await ethers.provider.getNetwork();
  console.log("network:", network);

  if (taskArgs.restartnonce) {
    console.log("Restarting from last submitted nonce.");
  }

  const { addresses, filenames } = getDeploymentData(network.chainId, taskArgs.production ? "production" : "staging");

  await hre.run("compile");

  const versions: IVersions = JSON.parse(fs.readFileSync(filenames.versionsFileName, "utf-8"));

  if (!versions) {
    throw new Error("No versions file");
  }
  const writeVersions = () => {
    const data = JSON.stringify(versions, null, 2);
    fs.writeFileSync(filenames.versionsFileName, data);
  };

  // TODO: This code needs to be reviewed and refactored
  const oldTag = Object.keys(versions)[Object.keys(versions).length - 1];
  let newTag: string;
  // I don't really understand this logic where if were not specifying jobs it doesnt use a new tag?
  if (!taskArgs.specific || taskArgs.keepversion) {
    newTag = oldTag;
    console.log(`Using Old Tag: ${oldTag}`);
  } else {
    // update to latest release version
    newTag = await getTag();
    console.log(`Using New Tag: ${newTag}`);
  }

  versions[newTag] = {
    contracts: { ...versions[oldTag].contracts },
    network: network,
    lastUpdated: new Date().toUTCString(),
  };

  // TODO: ^^This code needs to be reviewed and refactored

  try {
    await Promise.all(
      Object.keys(jobs)
        .filter((key) => {
          return !taskArgs.specific || taskArgs[key];
        })
        .map((key) =>
          jobs[key](
            { execute: taskArgs.execute, restartnonce: taskArgs.restartnonce, newTag, oldTag },
            hre,
            versions,
            filenames,
            addresses,
          ),
        ),
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
