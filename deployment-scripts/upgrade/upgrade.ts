import fs from "fs";
import { task, types } from "hardhat/config";
import { executeInSeries, getTag, nonceLog } from "../Helpers";
import { IJob, IVersions } from "../types";
import { getDeploymentData } from "./getDeploymentData";
import { erc20AssetGuardJob } from "./jobs/assetGuards/erc20AssetGuardJob";
import { lendingEnabledAssetGuardJob } from "./jobs/assetGuards/lendingEnabledAssetGuardJob";
import { quickLpAssetGuardJob } from "./jobs/assetGuards/quickLpAssetGuardJob";
import { sushiLpAssetGuardJob } from "./jobs/assetGuards/sushiLpAssetGuardJob";
import { uniV3AssetGuardJob } from "./jobs/assetGuards/uniV3AssetGuardJob";
import { aaveV3LendingPoolAssetGuardJob } from "./jobs/assetGuards/aaveV3LendingPoolAssetGuardJob";
import { assetHandlerJob } from "./jobs/assetHandlerJob";
import { assetsJob } from "./jobs/assetsJob";
import { aaveIncentivesControllerContractGuardJob } from "./jobs/contractGuards/aaveIncentivesControllerContractGuardJob";
import { aaveV2LendingPoolContractGuardJob } from "./jobs/contractGuards/aaveV2LendingPoolContractGuardJob";
import { balancerMerkleOrchardContractGuardJob } from "./jobs/contractGuards/balancerMerkleOrchardContractGuardJob";
import { balancerv2ContractGuard } from "./jobs/contractGuards/balancerv2ContractGuardJob";
import { easySwapperContractGuardJob } from "./jobs/contractGuards/easySwapperContractGuardJob";
import { oneInchV4ContractGuardJob } from "./jobs/contractGuards/oneInchV4ContractGuardJob";
import { quickStakingRewardsContractGuardJob } from "./jobs/contractGuards/quickStakingRewardsContractGuardJob";
import { sushiMiniChefV2ContractGuardJob } from "./jobs/contractGuards/sushiMiniChefV2ContractGuardJob";
import { uniswapV3NonFungiblePositionGuardJob } from "./jobs/contractGuards/uniswapV3NonFungiblePositionContractGuardJob";
import { v2RouterContractGuardJob } from "./jobs/contractGuards/v2RouterContractGuardJob"; //quickswapRouter, sushiswapV2Router etc etc
import { uniswapV3RouterContractGuardJob } from "./jobs/contractGuards/uniswapV3RouterContractGuardJob";
import { governanceNamesJob } from "./jobs/governanceNamesJob";
import { openAssetContractGuardJob } from "./jobs/otherWeirdGuards/openAssetContractGuardJob";
import { pauseJob } from "./jobs/pauseJob";
import { poolFactoryJob } from "./jobs/poolFactoryJob";
import { poolLogicJob } from "./jobs/poolLogicJob";
import { poolManagerLogicJob } from "./jobs/poolManagerLogicJob";
import { poolPerformanceJob } from "./jobs/poolPerformanceJobs";
import { unpauseJob } from "./jobs/unpauseJob";
import { aaveV2LendingPoolAssetGuardJob } from "./jobs/assetGuards/aaveV2LendingPoolAssetGuardJob";
import { aaveV3LendingPoolContractGuardJob } from "./jobs/contractGuards/aaveV3LendingPoolContractGuardJob";

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
  aavev2lendingpoolassetguard: aaveV2LendingPoolAssetGuardJob,
  aavev3lendingpoolassetguard: aaveV3LendingPoolAssetGuardJob,
  sushilpassetguard: sushiLpAssetGuardJob,
  erc20guard: erc20AssetGuardJob,
  lendingenabledassetguard: lendingEnabledAssetGuardJob,
  quicklpassetguard: quickLpAssetGuardJob,
  univ3assetguard: uniV3AssetGuardJob,

  // Contract Guards
  aavev2lendingpoolguard: aaveV2LendingPoolContractGuardJob,
  aavev3lendingpoolguard: aaveV3LendingPoolContractGuardJob,
  uniswapv2routerguard: v2RouterContractGuardJob,
  uniswapv3routerguard: uniswapV3RouterContractGuardJob,
  balancerv2guard: balancerv2ContractGuard,
  balancermerkleorchardguard: balancerMerkleOrchardContractGuardJob,
  quickstakingrewardsguard: quickStakingRewardsContractGuardJob,
  sushiminichefv2guard: sushiMiniChefV2ContractGuardJob,
  easyswapperguard: easySwapperContractGuardJob,
  aaveincentivescontrollerguard: aaveIncentivesControllerContractGuardJob,
  oneinchv4guard: oneInchV4ContractGuardJob,
  uniswapv3nonfungiblepositionguard: uniswapV3NonFungiblePositionGuardJob,

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
  console.log("Network:", network.name);

  if (taskArgs.restartnonce) {
    console.log("Restarting from last submitted nonce.");
  }

  console.log(`${taskArgs.production ? "Production" : "Staging"} environment.`);
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
    const jobsToRun = Object.keys(jobs)
      .filter((key) => {
        return !taskArgs.specific || taskArgs[key];
      })
      .map(
        (key) => () =>
          jobs[key](
            { execute: taskArgs.execute, restartnonce: taskArgs.restartnonce, newTag, oldTag },
            hre,
            versions,
            filenames,
            addresses,
          ),
      );
    await executeInSeries(jobsToRun);
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
