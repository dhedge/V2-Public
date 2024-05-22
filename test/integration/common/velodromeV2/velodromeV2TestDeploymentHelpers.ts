import { ethers } from "hardhat";

import {
  IBackboneDeployments,
  IBackboneDeploymentsParams,
  IERC20Path,
} from "../../utils/deployContracts/deployBackboneContracts";
import { AssetType } from "../../../../deployment/upgrade/jobs/assetsJob";
import { assetSetting } from "../../utils/deployContracts/getChainAssets";
import {
  IERC20,
  IVelodromeV2Gauge,
  IERC20__factory,
  IVelodromeV2Gauge__factory,
  IVelodromeV2Router__factory,
} from "../../../../types";

export type IVelodromeV2TestParams = IBackboneDeploymentsParams & {
  router: string;
  voter: string;
  factory: string;
  protocolToken: string;
  STABLE_USDC_DAI: { poolAddress: string; isStable: boolean; gaugeAddress: string };
  VARIABLE_WETH_USDC: { poolAddress: string; isStable: boolean; gaugeAddress: string };
  VARIABLE_PROTOCOLTOKEN_USDC: { poolAddress: string; isStable: boolean; gaugeAddress: string };
  assetsBalanceOfSlot: { usdc: number; dai: number };
};

export const iERC20 = new ethers.utils.Interface(IERC20__factory.abi);
export const iVelodromeRouter = new ethers.utils.Interface(IVelodromeV2Router__factory.abi);
export const iVelodromeGauge = new ethers.utils.Interface(IVelodromeV2Gauge__factory.abi);

export const deployVelodromeV2Infrastructure = async (
  deployments: IBackboneDeployments,
  testParams: IVelodromeV2TestParams,
) => {
  const VelodromeV2RouterGuard = await ethers.getContractFactory("VelodromeV2RouterGuard");
  const velodromeV2RouterGuard = await VelodromeV2RouterGuard.deploy();
  await velodromeV2RouterGuard.deployed();

  const VelodromeV2GaugeContractGuard = await ethers.getContractFactory("VelodromeV2GaugeContractGuard");
  const velodromeV2GaugeContractGuard = await VelodromeV2GaugeContractGuard.deploy();
  await velodromeV2GaugeContractGuard.deployed();

  const VelodromeV2LPAssetGuard = await ethers.getContractFactory("VelodromeV2LPAssetGuard");
  const velodromeV2LPAssetGuard = await VelodromeV2LPAssetGuard.deploy(testParams.voter);
  await velodromeV2LPAssetGuard.deployed();

  await deployments.governance.setContractGuard(testParams.router, velodromeV2RouterGuard.address);
  await deployments.governance.setContractGuard(
    testParams.VARIABLE_WETH_USDC.gaugeAddress,
    velodromeV2GaugeContractGuard.address,
  );
  await deployments.governance.setContractGuard(
    testParams.STABLE_USDC_DAI.gaugeAddress,
    velodromeV2GaugeContractGuard.address,
  );
  await deployments.governance.setAssetGuard(AssetType["Velodrome V2 LP/Gauge Asset"], velodromeV2LPAssetGuard.address);

  const VelodromeVariableLPAggregator = await ethers.getContractFactory("VelodromeVariableLPAggregator");
  const velodromeWethUsdcV2Aggregator = await VelodromeVariableLPAggregator.deploy(
    testParams.VARIABLE_WETH_USDC.poolAddress,
    deployments.poolFactory.address,
  );
  await velodromeWethUsdcV2Aggregator.deployed();

  const VelodromeStableLPAggregator = await ethers.getContractFactory("VelodromeStableLPAggregator");
  const velodromeUsdcDaiV2Aggregator = await VelodromeStableLPAggregator.deploy(
    testParams.STABLE_USDC_DAI.poolAddress,
    deployments.poolFactory.address,
  );
  await velodromeUsdcDaiV2Aggregator.deployed();

  const VelodromeV2TWAPAggregator = await ethers.getContractFactory("VelodromeV2TWAPAggregator");
  const velodromeV2TwapAggregator = await VelodromeV2TWAPAggregator.deploy(
    testParams.VARIABLE_PROTOCOLTOKEN_USDC.poolAddress,
    testParams.protocolToken,
    testParams.assets.usdc,
    testParams.usdPriceFeeds.usdc,
  );
  await velodromeV2TwapAggregator.deployed();

  await deployments.assetHandler.addAssets([
    assetSetting(
      testParams.VARIABLE_WETH_USDC.poolAddress,
      AssetType["Velodrome V2 LP/Gauge Asset"],
      velodromeWethUsdcV2Aggregator.address,
    ),
    assetSetting(
      testParams.STABLE_USDC_DAI.poolAddress,
      AssetType["Velodrome V2 LP/Gauge Asset"],
      velodromeUsdcDaiV2Aggregator.address,
    ),
    assetSetting(
      testParams.protocolToken,
      AssetType["Chainlink direct USD price feed with 8 decimals"],
      velodromeV2TwapAggregator.address,
    ),
  ]);

  const PROTOCOL_TOKEN = <IERC20>await ethers.getContractAt(IERC20Path, testParams.protocolToken);
  const USDC_DAI = <IERC20>await ethers.getContractAt(IERC20Path, testParams.STABLE_USDC_DAI.poolAddress);
  const USDC_DAI_GAUGE = <IVelodromeV2Gauge>(
    await ethers.getContractAt("IVelodromeV2Gauge", testParams.STABLE_USDC_DAI.gaugeAddress)
  );

  return {
    PROTOCOL_TOKEN,
    USDC_DAI,
    USDC_DAI_GAUGE,
    velodromeUsdcDaiV2Aggregator,
    velodromeWethUsdcV2Aggregator,
  };
};
