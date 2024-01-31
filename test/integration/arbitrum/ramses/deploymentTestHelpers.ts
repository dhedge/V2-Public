import { ethers } from "hardhat";
import { IBackboneDeployments } from "../../utils/deployContracts/deployBackboneContracts";
import { AssetType } from "../../../../deployment/upgrade/jobs/assetsJob";
import { assetSetting } from "../../utils/deployContracts/getChainAssets";
import { RamsesTestData } from "./RamsesLPTest";

export const deployRamsesInfrastructure = async (deployments: IBackboneDeployments, chainParams: RamsesTestData) => {
  const RamsesLPAssetGuard = await ethers.getContractFactory("RamsesLPAssetGuard");
  const ramsesLPAssetGuard = await RamsesLPAssetGuard.deploy(chainParams.ramsesVoter);
  await ramsesLPAssetGuard.deployed();
  await deployments.governance.setAssetGuard(AssetType["Ramses LP/Gauge Asset"], ramsesLPAssetGuard.address);

  const RamsesRouterContractGuard = await ethers.getContractFactory("RamsesRouterContractGuard");
  const ramsesRouterContractGuard = await RamsesRouterContractGuard.deploy();
  await ramsesRouterContractGuard.deployed();
  await deployments.governance.setContractGuard(chainParams.ramsesRouter, ramsesRouterContractGuard.address);

  const RamsesGaugeContractGuard = await ethers.getContractFactory("RamsesGaugeContractGuard");
  const ramsesGaugeContractGuard = await RamsesGaugeContractGuard.deploy();
  await ramsesGaugeContractGuard.deployed();

  const RamsesXRamContractGuard = await ethers.getContractFactory("RamsesXRamContractGuard");
  const ramsesXRamContractGuard = await RamsesXRamContractGuard.deploy();
  await ramsesXRamContractGuard.deployed();

  await deployments.governance.setContractGuard(chainParams.token0token1Gauge, ramsesGaugeContractGuard.address);
  await deployments.governance.setContractGuard(chainParams.token0token1Gauge_1, ramsesGaugeContractGuard.address);
  await deployments.governance.setContractGuard(chainParams.xoRam, ramsesXRamContractGuard.address);

  const RamsesLPAggregator = await ethers.getContractFactory(
    chainParams.token0token1IsStable ? "RamsesStableLPAggregator" : "RamsesVariableLPAggregator",
  );
  const token0tokenLPAggregator = await RamsesLPAggregator.deploy(
    chainParams.token0token1Pair,
    deployments.poolFactory.address,
  );
  await token0tokenLPAggregator.deployed();

  const RamsesTWAPAggregator = await ethers.getContractFactory("RamsesTWAPAggregator");
  const token1TWAPAggregator = await RamsesTWAPAggregator.deploy(
    chainParams.token0token1Pair,
    chainParams.token1, // main token - token to be priced
    chainParams.token0, // pair token - token to be priced against
    chainParams.usdPriceFeedToken0,
  );
  await token1TWAPAggregator.deployed();

  await deployments.assetHandler.addAssets([
    assetSetting(
      chainParams.token0,
      AssetType["Chainlink direct USD price feed with 8 decimals"],
      chainParams.usdPriceFeedToken0,
    ),
    assetSetting(
      chainParams.token1,
      AssetType["Chainlink direct USD price feed with 8 decimals"],
      token1TWAPAggregator.address,
    ),
    assetSetting(chainParams.token0token1Pair, AssetType["Ramses LP/Gauge Asset"], token0tokenLPAggregator.address),
    assetSetting(chainParams.token0token1Pair_1, AssetType["Ramses LP/Gauge Asset"], token0tokenLPAggregator.address),
  ]);

  return { token1TWAPAggregator, token0tokenLPAggregator };
};
