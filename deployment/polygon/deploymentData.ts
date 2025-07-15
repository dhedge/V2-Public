import fs from "fs";
import { polygonChainData } from "../../config/chainData/polygonData";
import { IAddresses, IFileNames } from "../types";
import { BigNumber } from "ethers";

const { aaveV3, torosPools, uniswapV3, assets, aaveV2 } = polygonChainData;

// Openzepplin doesn't support having two distinct deployments of the same contracts to the same chain.
// Itt always looks for the file "polygon.json" (previous unknown-137.json as 137 is the chainId).
// To be able to have two distinct deployments we switch files in and out as "polygon.json" depending on where we targeting to deploy
export const switchPolygonOzFile = (isProduction: boolean) => {
  console.log("Switching Polygon Openzepplin files.");
  const ozPath = "./.openzeppelin/";
  const ozEnvFile = ozPath + (isProduction ? "polygon-production.json" : "polygon-staging.json");
  const ozExpectedFile = ozPath + "polygon.json";
  fs.renameSync(ozEnvFile, ozExpectedFile);
  let renameComplete = false;
  const rename = () => {
    if (renameComplete) {
      return;
    }
    console.log("Process Exiting, Switching Back Filename");
    console.log("Renaming to ", ozEnvFile);
    try {
      fs.renameSync(ozExpectedFile, ozEnvFile);
      renameComplete = true;
    } catch (e) {
      console.error(`Could not rename ${ozEnvFile} back.`);
      console.error(e);
    }
    // eventually exit
    process.exit();
  };

  process.on("SIGINT", rename);
  process.on("exit", rename);
};

const polygonData: IAddresses = {
  // Dhedge Internal
  protocolDaoAddress: polygonChainData.protocolDao,
  protocolTreasuryAddress: polygonChainData.protocolTreasury,
  // Should be fetched from the oz file
  proxyAdminAddress: polygonChainData.proxyAdmin,

  balancerV2VaultAddress: polygonChainData.balancer.v2Vault,
  balancerMerkleOrchardAddress: polygonChainData.balancer.merkleOrchard,

  sushiMiniChefV2Address: polygonChainData.sushi.minichef,

  aaveV2: {
    aaveProtocolDataProviderAddress: aaveV2.protocolDataProvider,
    aaveLendingPoolAddress: aaveV2.lendingPool,
    aaveIncentivesControllerAddress: aaveV2.incentivesController,
  },

  aaveV3: {
    aaveLendingPoolAddress: aaveV3.lendingPool,
    aaveIncentivesControllerAddress: aaveV3.incentivesController,
  },

  aaveMigrationHelper: {
    migrationHelperAddress: "0x3db487975aB1728DB5787b798866c2021B24ec52",
    dHedgeVaultsWhitelist: [
      "0xf4b3a195587d2735b656b7ffe9060f478faf1b32", // Test vault with portfolio same as Ethereum Bear 2X
      "0xcc940b5c6136994bed41bff5d88b170929921e9e", // Test vault with portfolio same as Bitcoin Bear 2X
      assets.ETHBEAR2X,
      assets.BTCBEAR2X,
      assets.ETHBULL3X,
      assets.BTCBULL3X,
    ],
    aaveV3DebtTokensWhitelist: [
      aaveV3.variableDebtTokens.usdc,
      aaveV3.variableDebtTokens.weth,
      aaveV3.variableDebtTokens.wbtc,
    ],
  },

  quickStakingRewardsFactoryAddress: polygonChainData.quickswap.stakingRewardsFactory,
  quickLpUsdcWethStakingRewardsAddress: polygonChainData.quickswap.pools.usdc_weth.stakingRewards,
  quickswap: {
    uniV2Factory: polygonChainData.quickswap.factoryV2,
  },

  v2RouterAddresses: polygonChainData.v2Routers,

  oneInchV4RouterAddress: polygonChainData.oneinch.v4Router,
  oneInchV5RouterAddress: polygonChainData.oneinch.v5Router,
  oneInchV6RouterAddress: polygonChainData.oneinch.v6Router,

  uniV2: {
    factory: polygonChainData.uniswapV2.factory,
  },

  uniV3: {
    uniswapV3RouterAddress: uniswapV3.router,
    uniSwapV3NonfungiblePositionManagerAddress: uniswapV3.nonfungiblePositionManager,
    uniswapV3FactoryAddress: uniswapV3.factory,
  },

  arrakisV1: {
    arrakisV1RouterStakingAddress: polygonChainData.arrakis.v1RouterStaking,
  },

  assets: {
    nativeAssetWrapper: assets.wmatic,
    usdc: assets.usdc,
    weth: assets.weth,
    dai: assets.dai,
    dht: assets.dht,
  },

  easySwapperConfig: {
    customLockupAllowedPools: Object.values(torosPools),
    feeByPassManagers: [
      // Toros
      "0x090e7fbd87a673ee3d0b6ccacf0e1d94fb90da59",
    ],
    feeNumerator: 10, // 0.1% buy fee to enable Stablecoin Yield buys by managers at low cost and without need for secondary market
    feeDenominator: 10000,
  },

  stargate: {
    router: polygonChainData.stargate.router,
    staking: polygonChainData.stargate.staking,
  },

  superSwapper: {
    routeHints: polygonChainData.routeHints,
  },

  zeroExExchangeProxy: polygonChainData.zeroEx.exchangeProxy,

  slippageAccumulator: {
    decayTime: 86400, // 24 hours
    maxCumulativeSlippage: 10e4, // 10%
  },

  flatMoney: {
    swapper: polygonChainData.flatMoney.swapper,
  },

  easySwapperV2: {
    customCooldownDepositsWhitelist: [
      torosPools.BTCBEAR1X,
      torosPools.BTCBULL3X,
      torosPools.ETHBEAR1X,
      torosPools.ETHBULL3X,
      torosPools.MATICBEAR1X,
      torosPools.MATICBULL2X,
    ],
  },

  odosV2RouterAddress: polygonChainData.odosEx.v2Router,

  poolLimitOrderManager: {
    defaultSlippageTolerance: 200, // 2%
    settlementToken: polygonChainData.assets.usdcNative,
    authorizedKeeperAddresses: [
      "0xfF5C66B0799bb1cD834e2178866225F020A87A7f",
      "0xD411D209d3C602bdB7F99A16775A2e30aEb51009",
      "0xc804F6F95973f3380D8f52fd7aFF475337e2eea2",
      "0x83336A07e2257c537EfcA180E9c89819fa40ECCd",
      "0xfB2f4AE9584c82d3dB9Cd00B5CB664c8cf44470B",
    ],
  },
};

export const polygonProdData: IAddresses = {
  ...polygonData,
  stakingV2: {
    emissionsRate: 1000,
    dhtCap: BigNumber.from(2_000_000).mul(BigNumber.from(10).pow(18)),
    whitelistedPools: [
      // Polygon	Test Pool	https://app.dhedge.org/vault/0x5e0775919ee36e3e956622c01b8e8b64bd8eb7c5	$1,000
      { pool: "0x5e0775919ee36e3e956622c01b8e8b64bd8eb7c5", cap: BigNumber.from(1000).mul(BigNumber.from(10).pow(18)) },
    ],
  },
};

export const polygonStagingData: IAddresses = {
  ...polygonData,
  stakingV2: {
    emissionsRate: 1000,
    dhtCap: BigNumber.from(1_000).mul(BigNumber.from(10).pow(18)),
    whitelistedPools: [
      { pool: "0xfec92c0eebdefd1127440febd424d8e184826610", cap: BigNumber.from(1000).mul(BigNumber.from(10).pow(18)) },
      { pool: "0x14339e6e505b9b1f4806b166edf4a3512a2e1412", cap: BigNumber.from(1000).mul(BigNumber.from(10).pow(18)) },
      { pool: "0xe28c65873065327b984ab0459981c0c663140ada", cap: BigNumber.from(1000).mul(BigNumber.from(10).pow(18)) },
      { pool: "0xc95ced22defe7eadc5c23f423e5f614b8fdd618d", cap: BigNumber.from(1000).mul(BigNumber.from(10).pow(18)) },
    ],
  },
};

export const polygonStagingFileNames: IFileNames = {
  versionsFileName: "./publish/polygon/staging/versions.json",
  assetsFileName: "./config/polygonStaging/dHEDGE Assets list - Polygon Staging.json",
  governanceNamesFileName: "./config/polygonStaging/dHEDGE Governance Names - Polygon Staging.csv",
  contractGuardsFileName: "./config/polygonStaging/dHEDGE Governance Contract Guards - Polygon Staging.csv",
  assetGuardsFileName: "./config/polygonStaging/dHEDGE Governance Asset Guards - Polygon Staging.csv",
};

export const polygonProdFileNames: IFileNames = {
  versionsFileName: "./publish/polygon/prod/versions.json",
  assetsFileName: "./config/polygonProd/dHEDGE Assets list - Polygon.json",
  governanceNamesFileName: "./config/polygonProd/dHEDGE Governance Names - Polygon.csv",
  contractGuardsFileName: "./config/polygonProd/dHEDGE Governance Contract Guards - Polygon.csv",
  assetGuardsFileName: "./config/polygonProd/dHEDGE Governance Asset Guards - Polygon.csv",
  deprecatedContractGuardsFileName: "./config/polygonProd/dHEDGE Deprecated Contract Guards - Polygon.csv",
  externalAssetFileName: "./config/polygonProd/dHEDGE Assets list - Polygon External.csv",
};
