import { ethers } from "hardhat";

import { IBackboneDeployments, IBackboneDeploymentsParams } from "../../utils/deployContracts/deployBackboneContracts";
import { toBytes32 } from "../../../testHelpers";
import { AssetType } from "../../../../deployment/upgrade/jobs/assetsJob";
import { assetSetting } from "../../utils/deployContracts/getChainAssets";
import { IAaveV3Pool__factory } from "../../../../types";

export type IAaveV3TestParameters = IBackboneDeploymentsParams & {
  borrowAsset: string; // 18 decimals
  usdPriceFeeds: {
    borrowAsset: string;
  };
  assetsBalanceOfSlot: {
    usdc: number;
    weth: number;
    borrowAsset: number;
  };
  lendingPool: string;
  protocolDataProvider: string;
  uniswapV3: {
    factory: string;
    router: string;
  };
  velodromeV2?: {
    factory: string;
    router: string;
  };
  v2Routers: string[];
  incentivesController?: string;
  rewardToken?: string;
};

export const iLendingPool = new ethers.utils.Interface(IAaveV3Pool__factory.abi);

export const deployAaveV3TestInfrastructure = async (
  deployments: IBackboneDeployments,
  testParams: IAaveV3TestParameters,
) => {
  const AaveLendingPoolAssetGuard = await ethers.getContractFactory("AaveLendingPoolAssetGuard");
  const aaveLendingPoolAssetGuard = await AaveLendingPoolAssetGuard.deploy(
    testParams.protocolDataProvider,
    testParams.lendingPool,
  );
  await aaveLendingPoolAssetGuard.deployed();
  await deployments.governance.setAssetGuard(
    AssetType["Aave V3 Lending Pool Asset"],
    aaveLendingPoolAssetGuard.address,
  );

  const AaveLendingPoolGuardV3L2Pool = await ethers.getContractFactory("AaveLendingPoolGuardV3L2Pool");
  const aaveLendingPoolGuardV3L2Pool = await AaveLendingPoolGuardV3L2Pool.deploy();
  await aaveLendingPoolGuardV3L2Pool.deployed();
  await deployments.governance.setContractGuard(testParams.lendingPool, aaveLendingPoolGuardV3L2Pool.address);

  if (testParams.incentivesController) {
    const AaveIncentivesControllerV3Guard = await ethers.getContractFactory("AaveIncentivesControllerV3Guard");
    const aaveIncentivesControllerV3Guard = await AaveIncentivesControllerV3Guard.deploy();
    await aaveIncentivesControllerV3Guard.deployed();
    await deployments.governance.setContractGuard(
      testParams.incentivesController,
      aaveIncentivesControllerV3Guard.address,
    );
  }

  const uniV2LikeSwapRouters: string[] = [...testParams.v2Routers];

  const DhedgeUniV3V2Router = await ethers.getContractFactory("DhedgeUniV3V2Router");
  const dhedgeUniV3V2Router = await DhedgeUniV3V2Router.deploy(
    testParams.uniswapV3.factory,
    testParams.uniswapV3.router,
  );
  await dhedgeUniV3V2Router.deployed();
  uniV2LikeSwapRouters.push(dhedgeUniV3V2Router.address);

  if (testParams.velodromeV2) {
    const DhedgeVeloV2UniV2Router = await ethers.getContractFactory("DhedgeVeloV2UniV2Router");
    const dhedgeVeloUniV2Router = await DhedgeVeloV2UniV2Router.deploy(
      testParams.velodromeV2.router,
      testParams.velodromeV2.factory,
    );
    await dhedgeVeloUniV2Router.deployed();
    uniV2LikeSwapRouters.push(dhedgeVeloUniV2Router.address);
  }

  const DhedgeSuperSwapper = await ethers.getContractFactory("DhedgeSuperSwapper");
  const routeHints = [];
  const dhedgeSuperSwapper = await DhedgeSuperSwapper.deploy(uniV2LikeSwapRouters, routeHints);
  await dhedgeSuperSwapper.deployed();

  await deployments.governance.setAssetGuard(
    AssetType["Synthetix + LendingEnabled"],
    deployments.lendingEnabledAssetGuard.address,
  );

  await deployments.governance.setAddresses([
    { name: toBytes32("swapRouter"), destination: dhedgeSuperSwapper.address },
    { name: toBytes32("aaveProtocolDataProviderV3"), destination: testParams.protocolDataProvider },
    { name: toBytes32("weth"), destination: testParams.assets.weth },
  ]);

  await deployments.assetHandler.addAssets([
    assetSetting(
      testParams.lendingPool,
      AssetType["Aave V3 Lending Pool Asset"],
      deployments.usdPriceAggregator.address,
    ),
    // Re-set DAI to be non lending enabled
    assetSetting(
      testParams.assets.dai,
      AssetType["Chainlink direct USD price feed with 8 decimals"],
      testParams.usdPriceFeeds.dai,
    ),
  ]);

  await deployments.assetHandler.setChainlinkTimeout(3600 * 24 * 7); // 1 week expiry
};
