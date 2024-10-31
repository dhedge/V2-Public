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
import { RewardAssetSettingStruct } from "../../../../types/RewardAssetGuard";

export type IRamsesCLTestParams = IBackboneDeploymentsParams & {
  nonfungiblePositionManager: string;
  factory: string;
  voter: string;
  protocolToken: string;
  rewardTokenSettings: RewardAssetSettingStruct[];
  rewardTokensPriceFeeds: string[];
  pairs: {
    bothSupportedPair: {
      fee: number;
      tickSpacing: number;
      token0: string;
      token1: string;
      amount0: BigNumber;
      amount1: BigNumber;
      token0Slot: number;
      token1Slot: number;
      token0PriceFeed: string;
      token1PriceFeed: string;
    };
    token0UnsupportedPair?: {
      fee: number;
      token0: string;
      token1: string;
      amount0: BigNumber;
      amount1: BigNumber;
      token0Slot?: number;
      token1Slot?: number;
    };
    token1UnsupportedPair?: {
      fee: number;
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

export const deployRamsesCLInfrastructure = async (
  deployments: IBackboneDeployments,
  testParams: IRamsesCLTestParams,
) => {
  const DhedgeNftTrackerStorage = await ethers.getContractFactory("DhedgeNftTrackerStorage");
  const dhedgeNftTrackerStorage = <DhedgeNftTrackerStorage>(
    await upgrades.deployProxy(DhedgeNftTrackerStorage, [deployments.poolFactory.address])
  );
  await dhedgeNftTrackerStorage.deployed();

  const RamsesNonfungiblePositionGuard = await ethers.getContractFactory("RamsesNonfungiblePositionGuard");
  const ramsesNonfungiblePositionGuard = await RamsesNonfungiblePositionGuard.deploy(
    3,
    dhedgeNftTrackerStorage.address,
  );
  await ramsesNonfungiblePositionGuard.deployed();

  await deployments.governance.setContractGuard(
    testParams.nonfungiblePositionManager,
    ramsesNonfungiblePositionGuard.address,
  );

  const RamsesCLAssetGuard = await ethers.getContractFactory("RamsesCLAssetGuard");
  const ramsesCLAssetGuard = await RamsesCLAssetGuard.deploy(testParams.voter);
  await ramsesCLAssetGuard.deployed();

  await deployments.governance.setAssetGuard(AssetType["Ramses CL NFT Position Asset"], ramsesCLAssetGuard.address);

  const RewardAssetGuard = await ethers.getContractFactory("RewardAssetGuard");
  const rewardSettingParams: RewardAssetSettingStruct[] = testParams.rewardTokenSettings;
  const rewardAssetGuard = await RewardAssetGuard.deploy(rewardSettingParams);
  await rewardAssetGuard.deployed();

  await deployments.governance.setAssetGuard(AssetType["Reward Asset"], rewardAssetGuard.address);

  const nonfungiblePositionManager = await ethers.getContractAt(
    "IRamsesNonfungiblePositionManager",
    testParams.nonfungiblePositionManager,
  );

  const TestAsset = await ethers.getContractFactory("ERC20Asset");
  const testSupportedAsset = await TestAsset.deploy("Test", "TST");
  await testSupportedAsset.deployed();

  const USDPriceAggregator = await ethers.getContractFactory("USDPriceAggregator");
  const usdPriceAggregator = await USDPriceAggregator.deploy();
  await usdPriceAggregator.deployed();

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
      AssetType["Ramses CL NFT Position Asset"],
      usdPriceAggregator.address,
    ),
    ...testParams.rewardTokenSettings.map(({ rewardToken }, index) =>
      assetSetting(rewardToken, AssetType["Lending Enable Asset"], testParams.rewardTokensPriceFeeds[index]),
    ),
  ]);
  await deployments.assetHandler.setChainlinkTimeout(86400 * 365); // 365 days expiry

  const PROTOCOL_TOKEN = await ethers.getContractAt("IERC20", testParams.protocolToken);

  const voter = await ethers.getContractAt("IRamsesVoter", testParams.voter);
  const factory = await ethers.getContractAt("IUniswapV3Factory", testParams.factory);
  const poolAddress = await factory.getPool(
    testParams.pairs.bothSupportedPair.token0,
    testParams.pairs.bothSupportedPair.token1,
    testParams.pairs.bothSupportedPair.fee,
  );
  const gaugeAddress = await voter.gauges(poolAddress);
  const gauge = await ethers.getContractAt("IRamsesGaugeV2", gaugeAddress);

  return { nonfungiblePositionManager, ramsesNonfungiblePositionGuard, testSupportedAsset, PROTOCOL_TOKEN, gauge };
};
