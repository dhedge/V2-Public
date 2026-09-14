import fs from "fs";
import { task, types } from "hardhat/config";
import { executeInSeries, nonceLog, tryVerify } from "../deploymentHelpers";
import { IJob, IVersions } from "../types";
import { getDeploymentData } from "./getDeploymentData";
import { aaveV3LendingPoolAssetGuardJob } from "./jobs/assetGuards/aaveV3LendingPoolAssetGuardJob";
import { erc20GuardJob } from "./jobs/assetGuards/erc20AssetGuardJob";
import { uniV3AssetGuardJob } from "./jobs/assetGuards/uniV3AssetGuardJob";
import { assetHandlerJob } from "./jobs/assetHandlerJob";
import { assetsJob } from "./jobs/assetsJob";
import { aaveIncentivesControllerV3ContractGuardJob } from "./jobs/contractGuards/aaveIncentivesControllerV3ContractGuardJob";
import { aaveV3LendingPoolContractGuardJob } from "./jobs/contractGuards/aaveV3LendingPoolContractGuardJob";
import { uniswapV3NonFungiblePositionGuardJob } from "./jobs/contractGuards/uniswapV3NonFungiblePositionContractGuardJob";
import { nftTrackerJob } from "./jobs/nftTrackerJob";
import { pauseJob } from "./jobs/pauseJob";
import { poolFactoryJob } from "./jobs/poolFactoryJob";
import { poolLogicJob } from "./jobs/poolLogicJob";
import { poolLogicAndManagerLogicJob } from "./jobs/poolLogicAndManagerLogicJob";
import { poolManagerLogicJob } from "./jobs/poolManagerLogicJob";
import { removeAssetsJob } from "./jobs/removeAssetsJob";
import { rewardDistributionJob } from "./jobs/rewardDistributionJob";
import { dhedgeStakingV2NFTJSONJob } from "./jobs/stakingV2/dhedgeStakingNFTJsonJob";
import { dhedgeStakingV2Job } from "./jobs/stakingV2/dhedgeStakingV2Job";
import { superSwapperJob } from "./jobs/swapper/superSwapperJob";
import { swapperJob } from "./jobs/swapper/swapperJob";
import { uniV3V2RouterJob } from "./jobs/swapper/uniV3V2RouterJob";
import { veloUniV2RouterJob } from "./jobs/swapper/veloUniV2RouterJob";
import { unpauseJob } from "./jobs/unpauseJob";
import { dhedgeStakingV2ConfigurationJob } from "./jobs/stakingV2/dhedgeStakingV2ConfigurationJob";
import { slippageAccumulatorJob } from "./jobs/slippageAccumulatorJob";
import { velodromeV2GaugeContractGuardJob } from "./jobs/contractGuards/velodromeV2GaugeContractGuardJob";
import { velodromeV2RouterGuardJob } from "./jobs/contractGuards/velodromeV2RouterGuardJob";
import { velodromeV2LPAssetGuardJob } from "./jobs/assetGuards/velodromeV2LPAssetGuardJob";
import { veloV2UniV2RouterJob } from "./jobs/swapper/veloV2UniV2RouterJob";
import { deprecateContractGuardsJob } from "./jobs/deprecateContractGuardsJob";
import { closedContractGuardJob } from "./jobs/contractGuards/closedContractGuardJob";
import { ramsesUniV2RouterJob } from "./jobs/swapper/ramsesUniV2RouterJob";
import { aaveDebtTokenContractGuardJob } from "./jobs/contractGuards/aaveDebtTokenContractGuardJob";
import { flatMoneyDelayedOrderGuardJob } from "./jobs/contractGuards/flatMoneyDelayedOrderGuardJob";
import { flatMoneyCollateralAssetGuardJob } from "./jobs/assetGuards/flatMoneyCollateralAssetGuardJob";
import { flatMoneyUNITAssetGuardJob } from "./jobs/assetGuards/flatMoneyUNITAssetGuardJob";
import { oneInchV6ContractGuardJob } from "./jobs/contractGuards/oneInchV6ContractGuardJob";
import { velodromeCLAssetGuardJob } from "./jobs/assetGuards/velodromeCLAssetGuardJob";
import { velodromeNonfungiblePositionGuardJob } from "./jobs/contractGuards/velodromeNonfungiblePositionGuardJob";
import { enableVelodromeCLGaugeContractGuardJob } from "./jobs/velodromeCL/enableVelodromeCLGaugeContractGuardJob";
import { byPassAssetGuardJob } from "./jobs/assetGuards/byPassAssetGuardJob";
import { flatMoneyPerpMarketAssetGuardJob } from "./jobs/assetGuards/flatMoneyPerpMarketAssetGuardJob";
import { velodromeNonfungiblePositionGuardOldJob } from "./jobs/contractGuards/velodromeNonfungiblePositionGuardOldJob";
import { rewardAssetGuardJob } from "./jobs/assetGuards/rewardAssetGuardJob";
import { compoundV3CometRewardsContractGuardJob } from "./jobs/contractGuards/compoundV3CometRewardsContractGuardJob";
import { compoundV3CometAssetGuardJob } from "./jobs/assetGuards/compoundV3CometAssetGuardJob";
import { easySwapperV2Job } from "./jobs/easySwapperV2/easySwapperV2Job";
import { withdrawalVaultJob } from "./jobs/easySwapperV2/withdrawalVaultJob";
import { easySwapperV2ConfigurationJob } from "./jobs/easySwapperV2/easySwapperV2ConfigurationJob";
import { easySwapperV2ContractGuardJob } from "./jobs/contractGuards/easySwapperV2ContractGuardJob";
import { easySwapperV2UnrolledAssetsGuardJob } from "./jobs/assetGuards/easySwapperV2UnrolledAssetsGuardJob";
import { gmxExchangeRouterContractGuardJob } from "./jobs/contractGuards/gmxExchangeRouterContractGuardJob";
import { gmxPerpMarketAssetGuardJob } from "./jobs/assetGuards/gmxPerpMarketAssetGuardJob";
import { changeAssetsJob } from "./jobs/changeAssetsJob";
import { angleDistributorContractGuardJob } from "./jobs/contractGuards/angleDistributorContractGuardJob";
import { poolLimitOrderManagerJob } from "./jobs/poolLimitOrderManager/poolLimitOrderManagerJob";
import { poolLimitOrderManagerConfigurationJob } from "./jobs/poolLimitOrderManager/poolLimitOrderManagerConfigurationJob";
import { easyLimitBuyManagerJob } from "./jobs/easyLimitBuyManager/easyLimitBuyManagerJob";
import { easyLimitBuyManagerConfigurationJob } from "./jobs/easyLimitBuyManager/easyLimitBuyManagerConfigurationJob";
import { pancakeNonfungiblePositionGuardJob } from "./jobs/contractGuards/pancakeNonfungiblePositionGuardJob";
import { pancakeMasterChefV3GuardJob } from "./jobs/contractGuards/pancakeMasterChefV3GuardJob";
import { pancakeCLAssetGuardJob } from "./jobs/assetGuards/pancakeCLAssetGuardJob";
import { acrossContractGuardJob } from "./jobs/contractGuards/acrossContractGuardJob";
import { flatMoneyOptionsOrderAnnouncementGuardJob } from "./jobs/contractGuards/flatMoneyOptionsOrderAnnouncementGuardJob";
import { flatMoneyOptionsOrderExecutionGuardJob } from "./jobs/contractGuards/flatMoneyOptionsOrderExecutionGuardJob";
import { flatMoneyOptionsMarketAssetGuardJob } from "./jobs/assetGuards/flatMoneyOptionsMarketAssetGuardJob";
import { fluidTokenAssetGuardJob } from "./jobs/assetGuards/fluidTokenAssetGuardJob";
import { flatMoneyV2PerpMarketAssetGuardJob } from "./jobs/assetGuards/flatMoneyV2PerpMarketAssetGuardJob";
import { flatMoneyV2UNITAssetGuardJob } from "./jobs/assetGuards/flatMoneyV2UNITAssetGuardJob";
import { flatMoneyV2UNITOutsideWithdrawalAssetGuardJob } from "./jobs/assetGuards/flatMoneyV2UNITOutsideWithdrawalAssetGuardJob";
import { flatMoneyV2OrderAnnouncementGuardJob } from "./jobs/contractGuards/flatMoneyV2OrderAnnouncementGuardJob";
import { flatMoneyV2OrderExecutionGuardJob } from "./jobs/contractGuards/flatMoneyV2OrderExecutionGuardJob";
import { pendleRouterV4ContractGuardJob } from "./jobs/contractGuards/pendleRouterV4ContractGuardJob";
import { dytmOfficeContractGuardJob } from "./jobs/contractGuards/dytmOfficeContractGuardJob";
import { dytmWithdrawProcessorJob } from "./jobs/dytmWithdrawProcessorJob";
import { pendlePTAssetGuardJob } from "./jobs/assetGuards/pendlePTAssetGuardJob";
import { dytmOfficeAssetGuardJob } from "./jobs/assetGuards/dytmOfficeAssetGuardJob";
import { ondoGMTokenAssetGuardJob } from "./jobs/assetGuards/ondoGMTokenAssetGuardJob";
import { virtualTokenAssetGuardJob } from "./jobs/assetGuards/virtualTokenAssetGuardJob";
import { fluidMerkleDistributorContractGuardJob } from "./jobs/contractGuards/fluidMerkleDistributorContractGuardJob";
import { kyberSwapRouterV2ContractGuardJob } from "./jobs/contractGuards/kyberSwapRouterV2ContractGuardJob";
import { liquifiRewardsContractGuardJob } from "./jobs/contractGuards/liquifiRewardsContractGuardJob";
import { poolLimitOrderManagerGuardJob } from "./jobs/contractGuards/poolLimitOrderManagerGuardJob";
import { gpv2SettlementContractGuardJob } from "./jobs/contractGuards/gpv2SettlementContractGuardJob";
import { typedStructuredDataValidatorJob } from "./jobs/typedStructuredDataValidator/typedStructuredDataValidatorJob";
import { typedStructuredDataValidatorConfigurationJob } from "./jobs/typedStructuredDataValidator/typedStructuredDataValidatorConfigurationJob";
import { valueManipulationCheckJob } from "./jobs/valueManipulationCheckJob";
import { referralManagerJob } from "./jobs/referralManagerJob";
import { hyperliquidPositionGuardJob } from "./jobs/assetGuards/hyperliquidPositionGuardJob";
import { hyperliquidCoreWriterContractGuardJob } from "./jobs/contractGuards/hyperliquidCoreWriterContractGuardJob";
import { hyperliquidSpotGuardJob } from "./jobs/assetGuards/hyperliquidSpotGuardJob";
import { coreDepositWalletContractGuardJob } from "./jobs/contractGuards/coreDepositWalletContractGuardJob";
import { hyperliquidERC20GuardJob } from "./jobs/assetGuards/hyperliquidERC20GuardJob";
import { hyperliquidCoreWriterConfigurationJob } from "./jobs/contractGuards/hyperliquidCoreWriterConfigurationJob";
import { hyperliquidCoreWriterApiWalletJob } from "./jobs/contractGuards/hyperliquidCoreWriterApiWalletJob";
import { hyperliquidWithdrawalManagerJob } from "./jobs/hyperliquidWithdrawalManager/hyperliquidWithdrawalManagerJob";
import { ondoAttestationOracleJob } from "./jobs/ondo/ondoAttestationOracleJob";
import { ondoAttestationOracleConfigurationJob } from "./jobs/ondo/ondoAttestationOracleConfigurationJob";
import { ondoGMSwapJob } from "./jobs/ondo/ondoGMSwapJob";
import { ondoGMSwapConfigurationJob } from "./jobs/ondo/ondoGMSwapConfigurationJob";
import { ondoGMSwapContractGuardJob } from "./jobs/contractGuards/ondoGMSwapContractGuardJob";
import { midasRedemptionVaultContractGuardJob } from "./jobs/contractGuards/midasRedemptionVaultContractGuardJob";
import { midasDepositVaultContractGuardJob } from "./jobs/contractGuards/midasDepositVaultContractGuardJob";
import { midasMTokenAssetGuardJob } from "./jobs/assetGuards/midasMTokenAssetGuardJob";
import { midasPendingRedemptionAssetGuardJob } from "./jobs/assetGuards/midasPendingRedemptionAssetGuardJob";
import { withdrawalGuardianJob } from "./jobs/withdrawalGuardian/withdrawalGuardianJob";

const jobs: { [key: string]: IJob<void> } = {
  // Swappers related
  velouniv2router: veloUniV2RouterJob,
  velov2univ2router: veloV2UniV2RouterJob,
  univ3v2router: uniV3V2RouterJob,
  ramsesuniv2router: ramsesUniV2RouterJob,
  superswapper: superSwapperJob,
  swapper: swapperJob,

  // External
  rewarddistribution: rewardDistributionJob,
  slippageaccumulator: slippageAccumulatorJob,
  easylimitbuymanager: easyLimitBuyManagerJob,
  easylimitbuyconfig: easyLimitBuyManagerConfigurationJob,
  valuemanipulationcheck: valueManipulationCheckJob,

  pause: pauseJob,

  // Upgradable
  assethandler: assetHandlerJob,
  poolfactory: poolFactoryJob,
  poollogic: poolLogicJob,
  poolmanagerlogic: poolManagerLogicJob,
  poollogicandmanagerlogic: poolLogicAndManagerLogicJob,
  nfttracker: nftTrackerJob,
  poollimitordermanager: poolLimitOrderManagerJob,
  limitorderconfig: poolLimitOrderManagerConfigurationJob,
  typedstructureddatavalidator: typedStructuredDataValidatorJob,
  typedstructureddatavalidatorconfiguration: typedStructuredDataValidatorConfigurationJob,
  withdrawalguardian: withdrawalGuardianJob,
  referralmanager: referralManagerJob,
  ondoattestationoracle: ondoAttestationOracleJob,
  ondoattestationoracleconfiguration: ondoAttestationOracleConfigurationJob,
  ondogmswap: ondoGMSwapJob,
  ondogmswapconfig: ondoGMSwapConfigurationJob,
  hyperliquidwithdrawalmanager: hyperliquidWithdrawalManagerJob,

  // Dhedge Staking V2
  dhedgestakingv2nftjson: dhedgeStakingV2NFTJSONJob,
  dhedgestakingv2: dhedgeStakingV2Job,
  dhedgestakingv2configuration: dhedgeStakingV2ConfigurationJob,

  // Asset Guards
  aavev3lendingpoolassetguard: aaveV3LendingPoolAssetGuardJob,
  erc20guard: erc20GuardJob,
  univ3assetguard: uniV3AssetGuardJob,
  velodromev2lpassetguard: velodromeV2LPAssetGuardJob,
  flatmoneycollateralassetguard: flatMoneyCollateralAssetGuardJob,
  flatmoneyunitassetguard: flatMoneyUNITAssetGuardJob,
  velodromeclassetguard: velodromeCLAssetGuardJob,
  bypassassetguard: byPassAssetGuardJob,
  flatmoneyperpmarketassetguard: flatMoneyPerpMarketAssetGuardJob,
  rewardassetguard: rewardAssetGuardJob,
  compoundv3cometassetguard: compoundV3CometAssetGuardJob,
  easyswapperv2unrolledassetsguard: easySwapperV2UnrolledAssetsGuardJob,
  gmxperpmarketassetguard: gmxPerpMarketAssetGuardJob,
  pancakeclassetguard: pancakeCLAssetGuardJob,
  flatmoneyoptionsmarketassetguard: flatMoneyOptionsMarketAssetGuardJob,
  fluidtokenassetguard: fluidTokenAssetGuardJob,
  flatmoneyv2perpmarketassetguard: flatMoneyV2PerpMarketAssetGuardJob,
  flatmoneyv2unitassetguard: flatMoneyV2UNITAssetGuardJob,
  flatmoneyv2unitoutsidewithdrawalassetguard: flatMoneyV2UNITOutsideWithdrawalAssetGuardJob,
  pendleptassetguard: pendlePTAssetGuardJob,
  dytmwithdrawprocessor: dytmWithdrawProcessorJob,
  dytmofficeassetguard: dytmOfficeAssetGuardJob,
  ondogmtokenassetguard: ondoGMTokenAssetGuardJob,
  virtualtokenassetguard: virtualTokenAssetGuardJob,
  hyperliquidpositionguard: hyperliquidPositionGuardJob,
  hyperliquidspotguard: hyperliquidSpotGuardJob,
  hyperliquiderc20guard: hyperliquidERC20GuardJob,
  midasmtokenassetguard: midasMTokenAssetGuardJob,
  midaspendingredemptionassetguard: midasPendingRedemptionAssetGuardJob,

  // Contract Guards
  closedcontractguard: closedContractGuardJob,
  aavev3lendingpoolguard: aaveV3LendingPoolContractGuardJob,
  aaveincentivescontrollerv3guard: aaveIncentivesControllerV3ContractGuardJob,
  uniswapv3nonfungiblepositionguard: uniswapV3NonFungiblePositionGuardJob,
  velodromev2gaugecontractguard: velodromeV2GaugeContractGuardJob,
  velodromev2routerguard: velodromeV2RouterGuardJob,
  aavedebttokencontractguard: aaveDebtTokenContractGuardJob,
  flatmoneydelayedorderguard: flatMoneyDelayedOrderGuardJob,
  oneinchv6guard: oneInchV6ContractGuardJob,
  velodromenonfungiblepositionguard: velodromeNonfungiblePositionGuardJob,
  enablevelodromeclgaugecontractguard: enableVelodromeCLGaugeContractGuardJob,
  velodromenonfungiblepositionguardold: velodromeNonfungiblePositionGuardOldJob,
  compoundv3cometrewardscontractguard: compoundV3CometRewardsContractGuardJob,
  easyswapperv2contractguard: easySwapperV2ContractGuardJob,
  gmxexchangeroutercontractguard: gmxExchangeRouterContractGuardJob,
  angledistributorguard: angleDistributorContractGuardJob,
  pancakenonfungiblepositionguard: pancakeNonfungiblePositionGuardJob,
  pancakemasterchefv3guard: pancakeMasterChefV3GuardJob,
  acrosscontractguard: acrossContractGuardJob,
  flatmoneyoptionsorderannouncementguard: flatMoneyOptionsOrderAnnouncementGuardJob,
  flatmoneyoptionsorderexecutionguard: flatMoneyOptionsOrderExecutionGuardJob,
  flatmoneyv2orderannouncementguard: flatMoneyV2OrderAnnouncementGuardJob,
  flatmoneyv2orderexecutionguard: flatMoneyV2OrderExecutionGuardJob,
  pendlerouterv4contractguard: pendleRouterV4ContractGuardJob,
  fluidmerkledistributorcontractguard: fluidMerkleDistributorContractGuardJob,
  kyberswaprouterv2contractguard: kyberSwapRouterV2ContractGuardJob,
  liquifirewardscontractguard: liquifiRewardsContractGuardJob,
  poollimitordermanagerguard: poolLimitOrderManagerGuardJob,
  gpv2settlementcontractguard: gpv2SettlementContractGuardJob,
  dytmofficecontractguard: dytmOfficeContractGuardJob,
  hyperliquidcorewriterguard: hyperliquidCoreWriterContractGuardJob,
  hyperliquidcorewriterconfiguration: hyperliquidCoreWriterConfigurationJob,
  hyperliquidcorewriterapiwallet: hyperliquidCoreWriterApiWalletJob,
  coredepositwalletcontractguard: coreDepositWalletContractGuardJob,
  ondogmswapcontractguard: ondoGMSwapContractGuardJob,
  midasredemptionvaultcontractguard: midasRedemptionVaultContractGuardJob,
  midasdepositvaultcontractguard: midasDepositVaultContractGuardJob,

  // Governance
  assets: assetsJob,
  removeassets: removeAssetsJob,
  deprecatecontractguards: deprecateContractGuardsJob,
  changeassets: changeAssetsJob,

  // EasySwapperV2
  easyswapperv2: easySwapperV2Job,
  withdrawalvault: withdrawalVaultJob,
  easyswapperv2configuration: easySwapperV2ConfigurationJob,

  // Example of how to verify any contract that isn't verified
  // Can edit this job
  verifycontract: async (config, hre, versions) => {
    const contractAddress = versions[config.newTag].contracts.DhedgeUniV3V2Router;
    if (!contractAddress) return console.warn("DhedgeUniV3V2Router not deployed: nothing to verify.");
    await tryVerify(hre, contractAddress, "contracts/routers/DhedgeUniV3V2Router.sol:DhedgeUniV3V2Router", []);
  },

  // has to be last
  unpause: unpauseJob,
};

const upgradeTask = task("upgrade", "Upgrade contracts")
  .addParam("restartnonce", "propose transactions", false, types.boolean)
  .addOptionalParam("usenonce", "propose transactions", undefined, types.int)
  .addParam("execute", "propose transactions", false, types.boolean);

Object.keys(jobs).forEach((job) => {
  // We make each job a taskArg for hardhat :)
  upgradeTask.addOptionalParam(job, "run " + job, false, types.boolean);
});

upgradeTask.setAction(async (taskArgs, hre) => {
  // Checked before touching the network so a missing job fails instantly.
  const selectedJobs = Object.keys(jobs).filter((job) => taskArgs[job]);
  if (selectedJobs.length === 0) {
    throw new Error(
      "No upgrade jobs specified. Pass at least one, eg --poolfactory true. Run `pnpm hardhat help upgrade` for the full list.",
    );
  }

  const ethers = hre.ethers;
  const network = await ethers.provider.getNetwork();
  console.log("Network:", network.name);
  console.log(`Running ${selectedJobs.length} job(s): ${selectedJobs.join(", ")}`);

  if (taskArgs.restartnonce) {
    console.log("Restarting from last submitted nonce.");
  }

  const { addresses, filenames } = getDeploymentData(network.chainId);

  await hre.run("compile");

  const versions: IVersions = JSON.parse(fs.readFileSync(filenames.versionsFileName, "utf-8"));

  if (!versions) {
    throw new Error("No versions file");
  }
  const writeVersions = () => {
    const data = JSON.stringify(versions, null, 2);
    fs.writeFileSync(filenames.versionsFileName, data);
  };

  // Releases stopped being tagged after v2.12.0, so versions.json is a single
  // current entry that every deployment updates in place. Deployments no longer
  // consult git tags or create new version entries.
  const version = Object.keys(versions).pop();
  if (!version) {
    throw new Error(`No version entry in ${filenames.versionsFileName}`);
  }
  console.log(`Version entry: ${version}`);

  versions[version] = {
    ...versions[version],
    network,
    lastUpdated: new Date().toUTCString(),
  };

  try {
    const jobsToRun = selectedJobs.map(
      (key) => () =>
        jobs[key](
          {
            execute: taskArgs.execute,
            restartnonce: taskArgs.restartnonce,
            useNonce: taskArgs.usenonce,
            newTag: version,
            oldTag: version,
            chainId: network.chainId,
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
