import { ethers, upgrades } from "hardhat";

import { createFund } from "../../utils/createFund";
import { IBackboneDeployments } from "../../utils/deployContracts/deployBackboneContracts";
import { assetSetting } from "../../utils/deployContracts/getChainAssets";
import { AssetType } from "../../../../deployment/upgrade/jobs/assetsJob";

import { deduplicateTestTokenByAddress, IGmxTestsParams, TokenPriceConfig } from "./gmxTestHelpers";
import { OracleDataStruct } from "../../../../types/ChainlinkPythPriceAggregator";
import { DhedgeNftTrackerStorage } from "../../../../types";

export function createOracleData({
  oracleContractAddressOnchain,
  maxAgeOnchain,
  priceId,
  maxAgeOffchain,
  minConfidenceRatio,
}: TokenPriceConfig): OracleDataStruct {
  return {
    onchainOracle: {
      oracleContract: oracleContractAddressOnchain,
      maxAge: maxAgeOnchain,
    },
    offchainOracle: {
      priceId,
      maxAge: maxAgeOffchain,
      minConfidenceRatio,
    },
  };
}

export const deployGmxInfrastructure = async (deployments: IBackboneDeployments, deploymentParams: IGmxTestsParams) => {
  const USDPriceAggregator = await ethers.getContractFactory("USDPriceAggregator");
  const usdPriceAggregator = await USDPriceAggregator.deploy();
  await usdPriceAggregator.deployed();

  const GmxClaimableCollateralTrackerLib = await ethers.getContractFactory("GmxClaimableCollateralTrackerLib");
  const gmxClaimableCollateralTrackerLib = await GmxClaimableCollateralTrackerLib.deploy();

  const GmxPerpMarketAssetGuard = await ethers.getContractFactory("GmxPerpMarketAssetGuard", {
    libraries: {
      GmxClaimableCollateralTrackerLib: gmxClaimableCollateralTrackerLib.address,
    },
  });
  const gmxPerpMarketAssetGuard = await GmxPerpMarketAssetGuard.deploy(deploymentParams.exchangeRouter);
  await gmxPerpMarketAssetGuard.deployed();

  const assetType = AssetType["Gmx Perps Market Asset"];
  await deployments.governance.setAssetGuard(assetType, gmxPerpMarketAssetGuard.address);

  const testAssets = deduplicateTestTokenByAddress([
    deploymentParams.longCollateral,
    deploymentParams.shortCollateral,
    deploymentParams.gasToken,
  ]);

  // using chainlinkPythPriceAggregator for assets
  const assetPriceAggregators: string[] = [];
  const chainlinkPythPriceAggregator = await ethers.getContractFactory("ChainlinkPythPriceAggregator");
  for (const testAsset of testAssets) {
    const chainlinkPythPriceAggregatorInstanceCollateral = await chainlinkPythPriceAggregator.deploy(
      testAsset.address,
      deploymentParams.pythOracleContract,
      createOracleData({ ...testAsset.priceConfig }),
    );
    const priceAggregator = await chainlinkPythPriceAggregatorInstanceCollateral.deployed();
    assetPriceAggregators.push(priceAggregator.address);
  }

  await deployments.assetHandler.addAssets([
    ...testAssets.map((testAsset, index) =>
      assetSetting(
        testAsset.address,
        AssetType["Chainlink direct USD price feed with 8 decimals"],
        assetPriceAggregators[index],
      ),
    ),
    assetSetting(deploymentParams.market, AssetType["Gmx Perps Market Asset"], usdPriceAggregator.address),
  ]);

  const supportedAssets = [
    ...testAssets.map((testAsset) => ({
      asset: testAsset.address,
      isDeposit: true,
    })),
  ];

  const poolProxies = await createFund(
    deployments.poolFactory,
    deployments.owner,
    deployments.manager,
    supportedAssets,
    {
      performance: ethers.constants.Zero,
      management: ethers.constants.Zero,
    },
  );

  const DhedgeNftTrackerStorage = await ethers.getContractFactory("DhedgeNftTrackerStorage");
  const dhedgeNftTrackerStorage = <DhedgeNftTrackerStorage>(
    await upgrades.deployProxy(DhedgeNftTrackerStorage, [deployments.poolFactory.address])
  );
  await dhedgeNftTrackerStorage.deployed();

  const GmxAfterTxValidatorLib = await ethers.getContractFactory("GmxAfterTxValidatorLib", {
    libraries: {
      GmxClaimableCollateralTrackerLib: gmxClaimableCollateralTrackerLib.address,
    },
  });
  const gmxAfterTxValidatorLib = await GmxAfterTxValidatorLib.deploy();
  const GmxAfterExcutionLib = await ethers.getContractFactory("GmxAfterExcutionLib", {
    libraries: {
      GmxClaimableCollateralTrackerLib: gmxClaimableCollateralTrackerLib.address,
      GmxAfterTxValidatorLib: gmxAfterTxValidatorLib.address,
    },
  });
  const gmxAfterExcutionLib = await GmxAfterExcutionLib.deploy();
  const GmxHelperLib = await ethers.getContractFactory("GmxHelperLib");
  const gmxHelperLib = await GmxHelperLib.deploy();
  const GmxExchangeRouterContractGuard = await ethers.getContractFactory("GmxExchangeRouterContractGuard", {
    libraries: {
      GmxAfterTxValidatorLib: gmxAfterTxValidatorLib.address,
      GmxAfterExcutionLib: gmxAfterExcutionLib.address,
      GmxHelperLib: gmxHelperLib.address,
    },
  });

  // for virtural token oracle settings
  const extraPriceAggregators: string[] = [];
  for (const extraTokenSetting of deploymentParams.underlyingTokensToAdd) {
    const { address, ...priceConfig } = extraTokenSetting;
    const chainlinkPythPriceAggregatorInstanceCollateral = await chainlinkPythPriceAggregator.deploy(
      address,
      deploymentParams.pythOracleContract,
      createOracleData({ ...priceConfig }),
    );
    const priceAggregator = await chainlinkPythPriceAggregatorInstanceCollateral.deployed();
    extraPriceAggregators.push(priceAggregator.address);
  }

  await deployments.assetHandler.addAssets([
    // for adding mapped virtual token oracle, e.g. wbtc for btc index address
    ...deploymentParams.underlyingTokensToAdd.map((testAsset, index) =>
      assetSetting(
        testAsset.address,
        AssetType["Chainlink direct USD price feed with 8 decimals"],
        extraPriceAggregators[index],
      ),
    ),
  ]);

  const gmxExchangeRouterContractGuard = await GmxExchangeRouterContractGuard.deploy(
    {
      dataStore: deploymentParams.dataStore,
      reader: deploymentParams.reader,
      feeReceiver: deploymentParams.uiFeeReceiver,
      gmxExchangeRouter: deploymentParams.exchangeRouter,
      referralStorage: deploymentParams.referralStorage,
    },
    [
      {
        poolLogic: poolProxies.poolLogicProxy.address,
        withdrawalAsset: deploymentParams.longCollateral.address,
      },
    ],
    deploymentParams.vitrualTokenOracleSettings ?? [],
    deployments.slippageAccumulator.address,
    dhedgeNftTrackerStorage.address,
  );
  await gmxExchangeRouterContractGuard.deployed();

  await deployments.governance.setContractGuard(
    deploymentParams.exchangeRouter,
    gmxExchangeRouterContractGuard.address,
  );

  await poolProxies.poolManagerLogicProxy.changeAssets(
    [
      {
        asset: deploymentParams.market,
        isDeposit: false,
      },
    ],
    [],
  );

  const ClosedContractGuard = await ethers.getContractFactory("ClosedContractGuard");
  const closedContractGuard = await ClosedContractGuard.deploy();

  await deployments.governance.setContractGuard(deploymentParams.approvalRouter, closedContractGuard.address);

  await deployments.poolFactory.setExitCooldown(0);

  return {
    whitelistedPool: poolProxies,
    exchangeRouterAddress: deploymentParams.exchangeRouter,
    gmxClaimableCollateralTrackerLib,
    nftTracker: dhedgeNftTrackerStorage.address,
    gmxExchangeRouterContractGuard,
  };
};
