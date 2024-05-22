import { ethers, upgrades } from "hardhat";

import { IBackboneDeployments, IBackboneDeploymentsParams } from "../../utils/deployContracts/deployBackboneContracts";

import {
  IERC20__factory,
  IVelodromeCLGauge__factory,
  DhedgeNftTrackerStorage,
  IERC721__factory,
} from "../../../../types";
import { BigNumber } from "ethers";
import { assetSetting } from "../../utils/deployContracts/getChainAssets";
import { AssetType } from "../../../../deployment/upgrade/jobs/assetsJob";

export type IVelodromeCLTestParams = IBackboneDeploymentsParams & {
  nonfungiblePositionManager: string;
  factory: string;
  protocolToken: string;
  VARIABLE_PROTOCOLTOKEN_USDC: { poolAddress: string; isStable: boolean; gaugeAddress: string };
  pairs: {
    bothSupportedPair: {
      tickSpacing: number;
      token0: string;
      token1: string;
      amount0: BigNumber;
      amount1: BigNumber;
      token0Slot: number;
      token1Slot: number;
      token0PriceFeed: string;
      token1PriceFeed: string;
      gauge: string;
    };
    token0UnsupportedPair: {
      tickSpacing: number;
      token0: string;
      token1: string;
      amount0: BigNumber;
      amount1: BigNumber;
      token0Slot?: number;
      token1Slot?: number;
    };
    token1UnsupportedPair: {
      tickSpacing: number;
      token0: string;
      token1: string;
      amount0: BigNumber;
      amount1: BigNumber;
      token0Slot?: number;
      token1Slot?: number;
    };
  };
};

export const iERC20 = new ethers.utils.Interface(IERC20__factory.abi);
export const iERC721 = new ethers.utils.Interface(IERC721__factory.abi);
export const iVelodromeCLGauge = new ethers.utils.Interface(IVelodromeCLGauge__factory.abi);

export const deployVelodromeCLInfrastructure = async (
  deployments: IBackboneDeployments,
  testParams: IVelodromeCLTestParams,
) => {
  const DhedgeNftTrackerStorage = await ethers.getContractFactory("DhedgeNftTrackerStorage");
  const dhedgeNftTrackerStorage = <DhedgeNftTrackerStorage>(
    await upgrades.deployProxy(DhedgeNftTrackerStorage, [deployments.poolFactory.address])
  );
  await dhedgeNftTrackerStorage.deployed();

  const VelodromeNonfungiblePositionGuard = await ethers.getContractFactory("VelodromeNonfungiblePositionGuard");
  const velodromeNonfungiblePositionGuard = await VelodromeNonfungiblePositionGuard.deploy(
    3,
    dhedgeNftTrackerStorage.address,
  );
  await velodromeNonfungiblePositionGuard.deployed();

  await deployments.governance.setContractGuard(
    testParams.nonfungiblePositionManager,
    velodromeNonfungiblePositionGuard.address,
  );

  const VelodromeCLGaugeContractGuard = await ethers.getContractFactory("VelodromeCLGaugeContractGuard");
  const velodromeCLGaugeContractGuard = await VelodromeCLGaugeContractGuard.deploy();
  await velodromeCLGaugeContractGuard.deployed();

  await deployments.governance.setContractGuard(
    testParams.pairs.bothSupportedPair.gauge,
    velodromeCLGaugeContractGuard.address,
  );

  const VelodromeCLAssetGuard = await ethers.getContractFactory("VelodromeCLAssetGuard");
  const velodromeCLAssetGuard = await VelodromeCLAssetGuard.deploy();
  await velodromeCLAssetGuard.deployed();

  await deployments.governance.setAssetGuard(
    AssetType["Velodrome CL NFT Position Asset"],
    velodromeCLAssetGuard.address,
  );

  const nonfungiblePositionManager = await ethers.getContractAt(
    "IVelodromeNonfungiblePositionManager",
    testParams.nonfungiblePositionManager,
  );

  const TestAsset = await ethers.getContractFactory("ERC20Asset");
  const testSupportedAsset = await TestAsset.deploy("Test", "TST");
  await testSupportedAsset.deployed();

  const USDPriceAggregator = await ethers.getContractFactory("USDPriceAggregator");
  const usdPriceAggregator = await USDPriceAggregator.deploy();
  await usdPriceAggregator.deployed();

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
      testParams.pairs.bothSupportedPair.token0,
      AssetType["Chainlink direct USD price feed with 8 decimals"],
      testParams.pairs.bothSupportedPair.token0PriceFeed,
    ),
    assetSetting(
      testParams.pairs.bothSupportedPair.token1,
      AssetType["Chainlink direct USD price feed with 8 decimals"],
      testParams.pairs.bothSupportedPair.token1PriceFeed,
    ),
    assetSetting(
      testSupportedAsset.address,
      AssetType["Chainlink direct USD price feed with 8 decimals"],
      testParams.usdPriceFeeds.usdc,
    ),
    assetSetting(
      testParams.nonfungiblePositionManager,
      AssetType["Velodrome CL NFT Position Asset"],
      usdPriceAggregator.address,
    ),
    assetSetting(
      testParams.protocolToken,
      AssetType["Chainlink direct USD price feed with 8 decimals"],
      velodromeV2TwapAggregator.address,
    ),
  ]);
  await deployments.assetHandler.setChainlinkTimeout(86400 * 365); // 365 days expiry

  const PROTOCOL_TOKEN = await ethers.getContractAt("IERC20", testParams.protocolToken);

  return { nonfungiblePositionManager, velodromeNonfungiblePositionGuard, testSupportedAsset, PROTOCOL_TOKEN };
};
