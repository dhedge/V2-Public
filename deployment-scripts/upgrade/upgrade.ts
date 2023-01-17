import fs from "fs";
import { task, types } from "hardhat/config";
import { executeInSeries, getTag, nonceLog, tryVerify } from "../Helpers";
import { IJob, IVersions } from "../types";
import { getDeploymentData } from "./getDeploymentData";
import { aaveV2LendingPoolAssetGuardJob } from "./jobs/assetGuards/aaveV2LendingPoolAssetGuardJob";
import { aaveV3LendingPoolAssetGuardJob } from "./jobs/assetGuards/aaveV3LendingPoolAssetGuardJob";
import { arrakisLiquidityGaugeV4AssetGuardJob } from "./jobs/assetGuards/arrakisLiquidityGaugeV4AssetGuardJob";
import { lyraOptionMarketWrapperAssetGuardJob } from "./jobs/assetGuards/lyraOptionMarketWrapperAssetGuardJob";
import { balancerV2GaugeAssetGuardJob } from "./jobs/assetGuards/balancerV2GaugeAssetGuardJob";
import { erc20GuardJob } from "./jobs/assetGuards/erc20AssetGuardJob";
import { lendingEnabledAssetGuardJobGenerator } from "./jobs/assetGuards/lendingEnabledAssetGuardJob";
import { quickLpAssetGuardJob } from "./jobs/assetGuards/quickLpAssetGuardJob";
import { sushiLpAssetGuardJob } from "./jobs/assetGuards/sushiLpAssetGuardJob";
import { uniV3AssetGuardJob } from "./jobs/assetGuards/uniV3AssetGuardJob";
import { velodromeLPAssetGuardJob } from "./jobs/assetGuards/velodromeLPAssetGuardJob";
import { assetHandlerJob } from "./jobs/assetHandlerJob";
import { assetsJob } from "./jobs/assetsJob";
import { aaveIncentivesControllerContractGuardJob } from "./jobs/contractGuards/aaveIncentivesControllerContractGuardJob";
import { aaveIncentivesControllerV3ContractGuardJob } from "./jobs/contractGuards/aaveIncentivesControllerV3ContractGuardJob";
import { aaveV2LendingPoolContractGuardJob } from "./jobs/contractGuards/aaveV2LendingPoolContractGuardJob";
import { aaveV3LendingPoolContractGuardJob } from "./jobs/contractGuards/aaveV3LendingPoolContractGuardJob";
import { arrakisLiquidityGaugeV4ContractGuardJob } from "./jobs/contractGuards/arrakisLiquidityGaugeV4ContractGuardJob";
import { arrakisV1RouterStakingContractGuardJob } from "./jobs/contractGuards/arrakisV1RouterStakingContractGuardJob";
import { lyraOptionMarketWrapperContractGuardJob } from "./jobs/contractGuards/lyraOptionMarketWrapperContractGuardJob";
import { balancerMerkleOrchardContractGuardJob } from "./jobs/contractGuards/balancerMerkleOrchardContractGuardJob";
import { balancerv2ContractGuard } from "./jobs/contractGuards/balancerv2ContractGuardJob";
import { balancerV2GaugeContractGuardJob } from "./jobs/contractGuards/balancerV2GaugeContractGuardJob";
import { easySwapperContractGuardJob } from "./jobs/contractGuards/easySwapperContractGuardJob";
import { oneInchV4ContractGuardJob } from "./jobs/contractGuards/oneInchV4ContractGuardJob";
import { oneInchV5ContractGuardJob } from "./jobs/contractGuards/oneInchV5ContractGuardJob";
import { quickStakingRewardsContractGuardJob } from "./jobs/contractGuards/quickStakingRewardsContractGuardJob";
import { sushiMiniChefV2ContractGuardJob } from "./jobs/contractGuards/sushiMiniChefV2ContractGuardJob";
import { uniswapV3NonFungiblePositionGuardJob } from "./jobs/contractGuards/uniswapV3NonFungiblePositionContractGuardJob";
import { uniswapV3RouterContractGuardJob } from "./jobs/contractGuards/uniswapV3RouterContractGuardJob";
import { v2RouterContractGuardJob } from "./jobs/contractGuards/v2RouterContractGuardJob"; //quickswapRouter, sushiswapV2Router etc etc
import { velodromeGaugeContractGuardJob } from "./jobs/contractGuards/velodromeGaugeContractGuardJob";
import { velodromeRouterGuardJob } from "./jobs/contractGuards/velodromeRouterGuardJob";
import { easySwapperJob } from "./jobs/swapper/easySwapperJob";
import { governanceNamesJob } from "./jobs/governanceNamesJob";
import { openAssetContractGuardJob } from "./jobs/otherWeirdGuards/openAssetContractGuardJob";
import { pauseJob } from "./jobs/pauseJob";
import { poolFactoryJob } from "./jobs/poolFactoryJob";
import { poolLogicJob } from "./jobs/poolLogicJob";
import { poolManagerLogicJob } from "./jobs/poolManagerLogicJob";
import { dhedgeStakingV2Job } from "./jobs/stakingV2/dhedgeStakingV2Job";
import { rewardDistributionJob } from "./jobs/rewardDistributionJob";
import { removeAssetsJob } from "./jobs/removeAssetsJob";
import { dhedgeStakingV2NFTJSONJob } from "./jobs/stakingV2/dhedgeStakingNFTJsonJob";
import { superSwapperJob } from "./jobs/swapper/superSwapperJob";
import { unpauseJob } from "./jobs/unpauseJob";
import { erc721ContractGuardJob } from "./jobs/contractGuards/erc721ContractGuardJob";
import { nftTrackerJob } from "./jobs/nftTrackerJob";
import { lyraMarketsContractGuardJob } from "./jobs/contractGuards/lyraMarketsContractGuardJob";
import { dhedgeOptionMarketWrapperForLyraJob } from "./jobs/assetGuards/dhedgeOptionMarketWrapperForLyraJob";
import { veloV2RouterJob } from "./jobs/swapper/veloV2RouterJob";
import { uniV3V2RouterJob } from "./jobs/swapper/uniV3V2RouterJob";
import { futuresMarketContractGuardJob } from "./jobs/contractGuards/futuresMarketContractGuardJob";
import { futuresMarketAssetGuardJob } from "./jobs/assetGuards/futuresMarketAssetGuardJob";

const jobs: { [key: string]: IJob<void> } = {
  // External
  velov2router: veloV2RouterJob,
  univ3v2router: uniV3V2RouterJob,
  superswapper: superSwapperJob,
  easyswapper: easySwapperJob,
  rewarddistribution: rewardDistributionJob,

  pause: pauseJob,

  // Upgradable
  assets: assetsJob,
  removeassets: removeAssetsJob,
  assethandler: assetHandlerJob,
  poolfactory: poolFactoryJob,
  poollogic: poolLogicJob,
  poolmanagerlogic: poolManagerLogicJob,
  nfttracker: nftTrackerJob,

  // Dhedge Staking V2
  dhedgestakingv2nftjson: dhedgeStakingV2NFTJSONJob,
  dhedgestakingv2: dhedgeStakingV2Job,

  // Asset Guards
  aavev2lendingpoolassetguard: aaveV2LendingPoolAssetGuardJob,
  aavev3lendingpoolassetguard: aaveV3LendingPoolAssetGuardJob,
  sushilpassetguard: sushiLpAssetGuardJob,
  erc20guard: erc20GuardJob,
  erc721guard: erc721ContractGuardJob,
  lendingenabledassetguard: lendingEnabledAssetGuardJobGenerator(4),
  synthetixlendingenabledassetguard: lendingEnabledAssetGuardJobGenerator(14),
  quicklpassetguard: quickLpAssetGuardJob,
  univ3assetguard: uniV3AssetGuardJob,
  arrakisliquiditygaugev4assetguard: arrakisLiquidityGaugeV4AssetGuardJob,
  dhedgeoptionmarketwrapperforlyra: dhedgeOptionMarketWrapperForLyraJob,
  lyraoptionmarketwrapperassetguard: lyraOptionMarketWrapperAssetGuardJob,
  balancerv2gaugeassetguard: balancerV2GaugeAssetGuardJob,
  velodromelpassetguard: velodromeLPAssetGuardJob,
  futuresmarketassetguard: futuresMarketAssetGuardJob,

  // Contract Guards
  aavev2lendingpoolguard: aaveV2LendingPoolContractGuardJob,
  aavev3lendingpoolguard: aaveV3LendingPoolContractGuardJob,
  uniswapv2routerguard: v2RouterContractGuardJob,
  uniswapv3routerguard: uniswapV3RouterContractGuardJob,
  velodromerouterguard: velodromeRouterGuardJob,
  balancerv2guard: balancerv2ContractGuard,
  balancerv2gaugecontractguard: balancerV2GaugeContractGuardJob,
  balancermerkleorchardguard: balancerMerkleOrchardContractGuardJob,
  quickstakingrewardsguard: quickStakingRewardsContractGuardJob,
  sushiminichefv2guard: sushiMiniChefV2ContractGuardJob,
  easyswapperguard: easySwapperContractGuardJob,
  aaveincentivescontrollerguard: aaveIncentivesControllerContractGuardJob,
  aaveincentivescontrollerv3guard: aaveIncentivesControllerV3ContractGuardJob,
  oneinchv4guard: oneInchV4ContractGuardJob,
  oneinchv5guard: oneInchV5ContractGuardJob,
  uniswapv3nonfungiblepositionguard: uniswapV3NonFungiblePositionGuardJob,
  arrakisliquiditygaugev4guard: arrakisLiquidityGaugeV4ContractGuardJob,
  arrakisv1routerstakingguard: arrakisV1RouterStakingContractGuardJob,
  velodromegaugecontractguard: velodromeGaugeContractGuardJob,
  futuresmarketcontractguard: futuresMarketContractGuardJob,

  lyraoptionmarketwrappercontractguard: lyraOptionMarketWrapperContractGuardJob,
  lyramarketscontractguard: lyraMarketsContractGuardJob,

  // Other Weird Guards
  openassetguard: openAssetContractGuardJob,

  // Governance
  governancenames: governanceNamesJob,

  lyraGroup: async (...args) => {
    await nftTrackerJob(...args);
    await erc721ContractGuardJob(...args);
    await lyraOptionMarketWrapperContractGuardJob(...args);
    await dhedgeOptionMarketWrapperForLyraJob(...args);
    await lyraOptionMarketWrapperAssetGuardJob(...args);
    await lyraMarketsContractGuardJob(...args);
    await assetsJob(...args);
  },

  // Example of how to verify any contract that isn't verified
  // Can edit this job
  verifycontract: async (config, hre, versions) => {
    const assets = versions[config.newTag].contracts.Assets;

    for (const a of assets) {
      if (a.oracleType == "VelodromeVariableLPAggregator") {
        await tryVerify(
          hre,
          a.oracleAddress,
          "contracts/priceAggregators/VelodromeVariableLPAggregator.sol:VelodromeVariableLPAggregator",
          [a.assetAddress, a.specificOracleConfig.dhedgeFactoryProxy],
        );
      }
    }
  },

  // has to be last
  unpause: unpauseJob,
};

const upgradeTask = task("upgrade", "Upgrade contracts")
  .addParam("production", "run in production environment", false, types.boolean)
  .addParam("restartnonce", "propose transactions", false, types.boolean)
  .addOptionalParam("usenonce", "propose transactions", undefined, types.int)
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

  try {
    const jobsToRun = Object.keys(jobs)
      .filter((key) => {
        return !taskArgs.specific || taskArgs[key];
      })
      .map(
        (key) => () =>
          jobs[key](
            {
              execute: taskArgs.execute,
              restartnonce: taskArgs.restartnonce,
              useNonce: taskArgs.usenonce,
              newTag,
              oldTag,
            },
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
    if (taskArgs.execute) {
      console.log("Updating versions.json");
      writeVersions();
      console.log("Updating csv");
      // TODO: Shouldn't be using a mutable export/import to pass out this data
      nonceLog.forEach((nl) => {
        console.log("- ", nl.nonce, " - ", nl.message);
      });
    }
  }
});
