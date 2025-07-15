import { ethers } from "hardhat";
import { BigNumber } from "ethers";

import { IBackboneDeployments, IBackboneDeploymentsParams } from "../../utils/deployContracts/deployBackboneContracts";
import { AssetType } from "../../../../deployment/upgrade/jobs/assetsJob";
import { assetSetting } from "../../utils/deployContracts/getChainAssets";
import { IAaveV3Pool__factory } from "../../../../types";
import { getOneInchSwapTransaction } from "../../utils/oneInchHelpers";
import { ChainIds, utils } from "../../utils/utils";
import { ComplexAssetStruct, PoolLogic } from "../../../../types/PoolLogic";

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
  swapper: string;
  chainId: ChainIds;
};

export const iLendingPool = new ethers.utils.Interface(IAaveV3Pool__factory.abi);

export const deployAaveV3TestInfrastructure = async (
  deployments: IBackboneDeployments,
  testParams: IAaveV3TestParameters,
) => {
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

  await deployments.governance.setAssetGuard(AssetType["Synthetix + LendingEnabled"], deployments.erc20Guard.address);

  const AaveLendingPoolAssetGuard = await ethers.getContractFactory("AaveLendingPoolAssetGuard");
  const aaveLendingPoolAssetGuard = await AaveLendingPoolAssetGuard.deploy(
    testParams.lendingPool,
    testParams.swapper,
    dhedgeSuperSwapper.address,
    5,
    10_000,
    10_000,
  );
  await aaveLendingPoolAssetGuard.deployed();
  await deployments.governance.setAssetGuard(
    AssetType["Aave V3 Lending Pool Asset"],
    aaveLendingPoolAssetGuard.address,
  );

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

const getSupportedAssets = async (poolLogicProxy: PoolLogic) => {
  const poolManagerLogicAddress = await poolLogicProxy.poolManagerLogic();
  const poolManagerLogic = await ethers.getContractAt("PoolManagerLogic", poolManagerLogicAddress);
  return poolManagerLogic.getSupportedAssets();
};

export const getComplexAssetsData = async (
  deployments: Pick<IBackboneDeployments, "poolFactory">,
  testParams: Pick<IAaveV3TestParameters, "lendingPool" | "swapper" | "chainId">,
  poolLogicProxy: PoolLogic,
  withdrawAmount: BigNumber,
): Promise<ComplexAssetStruct[]> => {
  const aaveAssetGuardAddress = await deployments.poolFactory.getAssetGuard(testParams.lendingPool);
  const assetGuard = await ethers.getContractAt("AaveLendingPoolAssetGuard", aaveAssetGuardAddress);
  const slippageTolerance = 60; // 0.6%
  const { srcData, dstData } = await assetGuard.callStatic.calculateSwapDataParams(
    poolLogicProxy.address,
    withdrawAmount,
    slippageTolerance,
  );

  const srcDataToEncode: unknown[] = [];
  const routerKey = ethers.utils.formatBytes32String("ONE_INCH");

  for (const { asset, amount } of srcData) {
    const swapData = await getOneInchSwapTransaction({
      src: asset,
      amount,
      dst: dstData.asset,
      chainId: testParams.chainId,
      from: testParams.swapper,
      receiver: testParams.swapper,
      version: "6.0",
    });
    srcDataToEncode.push([asset, amount, [routerKey, swapData]]);
    await utils.delay(2);
  }

  const encodedSrcData = ethers.utils.defaultAbiCoder.encode(
    ["tuple(address, uint256, tuple(bytes32, bytes))[]"],
    [srcDataToEncode],
  );
  const withdrawData = ethers.utils.defaultAbiCoder.encode(
    ["tuple(bytes, tuple(address, uint256), uint256)"],
    [[encodedSrcData, [dstData.asset, dstData.amount], slippageTolerance]],
  );

  const supportedAssets = await getSupportedAssets(poolLogicProxy);
  return supportedAssets.map(({ asset }) => ({
    supportedAsset: asset,
    withdrawData: asset === testParams.lendingPool ? withdrawData : [],
    slippageTolerance: asset === testParams.lendingPool ? slippageTolerance : 0,
  }));
};

export const getEmptyComplexAssetsData = async (poolLogicProxy: PoolLogic): Promise<ComplexAssetStruct[]> => {
  const supportedAssets = await getSupportedAssets(poolLogicProxy);
  return supportedAssets.map(({ asset }) => ({
    supportedAsset: asset,
    withdrawData: [],
    slippageTolerance: 0,
  }));
};
