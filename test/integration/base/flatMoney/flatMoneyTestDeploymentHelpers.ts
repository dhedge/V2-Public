import { ethers, upgrades } from "hardhat";
import { IBackboneDeployments, IBackboneDeploymentsParams } from "../../utils/deployContracts/deployBackboneContracts";
import { AssetType } from "../../../../deployment/upgrade/jobs/assetsJob";
import { assetSetting } from "../../utils/deployContracts/getChainAssets";
import { DhedgeNftTrackerStorage } from "../../../../types";

export type IFlatMoneyTestParams = IBackboneDeploymentsParams & {
  delayedOrder: string;
  viewer: string;
  pointsModule: string;
  UNIT: {
    address: string;
  };
  collateralAsset: {
    address: string;
    priceFeed: string;
    balanceOfSlot: number;
  };
  leverageModule: string;
  oracleModule: string;
  withdrawalAsset: {
    address: string;
    priceFeed: string;
    balanceOfSlot: number;
  };
};

export const deployFlatMoneyInfrastructure = async (
  deployments: IBackboneDeployments,
  testParams: IFlatMoneyTestParams,
) => {
  const DhedgeNftTrackerStorage = await ethers.getContractFactory("DhedgeNftTrackerStorage");
  const dhedgeNftTrackerStorage = <DhedgeNftTrackerStorage>(
    await upgrades.deployProxy(DhedgeNftTrackerStorage, [deployments.poolFactory.address])
  );
  await dhedgeNftTrackerStorage.deployed();

  const FlatMoneyDelayedOrderContractGuard = await ethers.getContractFactory("FlatMoneyDelayedOrderContractGuard");
  const flatMoneyDelayedOrderContractGuard = await FlatMoneyDelayedOrderContractGuard.deploy(
    dhedgeNftTrackerStorage.address,
    [],
  );
  await flatMoneyDelayedOrderContractGuard.deployed();

  await deployments.governance.setContractGuard(testParams.delayedOrder, flatMoneyDelayedOrderContractGuard.address);

  const FlatMoneyUNITAssetGuard = await ethers.getContractFactory("FlatMoneyUNITAssetGuard");
  const flatMoneyUNITAssetGuard = await FlatMoneyUNITAssetGuard.deploy();
  await flatMoneyUNITAssetGuard.deployed();

  const FlatMoneyCollateralAssetGuard = await ethers.getContractFactory("FlatMoneyCollateralAssetGuard");
  const flatMoneyCollateralAssetGuard = await FlatMoneyCollateralAssetGuard.deploy(testParams.delayedOrder);
  await flatMoneyCollateralAssetGuard.deployed();

  await deployments.governance.setAssetGuard(AssetType["Flat Money's UNIT"], flatMoneyUNITAssetGuard.address);
  await deployments.governance.setAssetGuard(
    AssetType["Flat Money's Collateral"],
    flatMoneyCollateralAssetGuard.address,
  );

  const FlatMoneyPerpMarketAssetGuard = await ethers.getContractFactory("FlatMoneyPerpMarketAssetGuard");
  const flatMoneyPerpMarketAssetGuard = await FlatMoneyPerpMarketAssetGuard.deploy();
  await flatMoneyPerpMarketAssetGuard.deployed();

  await deployments.governance.setAssetGuard(
    AssetType["Flat Money's Leverage Asset"],
    flatMoneyPerpMarketAssetGuard.address,
  );

  /* Using modified contract for testing because during time travel getting price sometimes fails with weird error */
  const FlatMoneyUNITPriceAggregator = await ethers.getContractFactory("FlatMoneyUNITPriceAggregatorTest");
  const flatMoneyUNITPriceAggregator = await FlatMoneyUNITPriceAggregator.deploy(testParams.viewer);
  await flatMoneyUNITPriceAggregator.deployed();

  await deployments.assetHandler.addAssets([
    assetSetting(
      testParams.collateralAsset.address,
      AssetType["Flat Money's Collateral"],
      testParams.collateralAsset.priceFeed,
    ),
    assetSetting(
      testParams.leverageModule,
      AssetType["Flat Money's Leverage Asset"],
      deployments.usdPriceAggregator.address,
    ),
    assetSetting(testParams.UNIT.address, AssetType["Flat Money's UNIT"], flatMoneyUNITPriceAggregator.address),
  ]);

  await deployments.poolFactory.setExitCooldown(0);

  return {
    flatMoneyDelayedOrderContractGuard,
  };
};
