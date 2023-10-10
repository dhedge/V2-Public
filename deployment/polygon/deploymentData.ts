import fs from "fs";
import { polygonChainData } from "../../config/chainData/polygonData";
import { IAddresses, IFileNames } from "../types";
import { BigNumber } from "ethers";
import { implementationStorageAddress } from "../common/deploymentData";

const { aaveV3, torosPools, uniswapV3, assets } = polygonChainData;

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

const polygonAddresses: IAddresses = {
  // Dhedge Internal
  protocolDaoAddress: polygonChainData.protocolDao,
  protocolTreasuryAddress: "0x6f005cbceC52FFb28aF046Fd48CB8D6d19FD25E3",
  // Should be fetched from the oz file
  proxyAdminAddress: polygonChainData.proxyAdmin,
  // Same for everyone
  implementationStorageAddress,
  // Gnosis safe multicall/send address
  // https://github.com/gnosis/safe-deployments
  gnosisMultiSendAddress: "0xA238CBeb142c10Ef7Ad8442C6D1f9E89e07e7761",
  gnosisApi: "https://safe-transaction-polygon.safe.global",

  // External Logic Contracts
  balancerV2VaultAddress: "0xBA12222222228d8Ba445958a75a0704d566BF2C8",
  balancerMerkleOrchardAddress: "0x0F3e0c4218b7b0108a3643cFe9D3ec0d4F57c54e",
  sushiMiniChefV2Address: "0x0769fd68dFb93167989C6f7254cd0D766Fb2841F",
  aaveIncentivesControllerAddress: "0x357D51124f59836DeD84c8a1730D72B749d8BC23",
  aaveV2: {
    aaveProtocolDataProviderAddress: "0x7551b5D2763519d4e37e8B81929D336De671d46d",
    aaveLendingPoolAddress: "0x8dFf5E27EA6b7AC08EbFdf9eB090F32ee9a30fcf",
  },

  aaveV3: {
    aaveProtocolDataProviderAddress: aaveV3.protocolDataProvider,
    aaveLendingPoolAddress: aaveV3.lendingPool,
    aaveIncentivesControllerAddress: aaveV3.incentivesController,
  },

  quickStakingRewardsFactoryAddress: "0x5eec262B05A57da9beb5FE96a34aa4eD0C5e029f",
  v2RouterAddresses: ["0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506", "0xa5E0829CaCEd8fFDD4De3c43696c57F7D7A678ff"], //quickswapRouter, sushiswapV2Router etc etc
  quickLpUsdcWethStakingRewardsAddress: "0x4A73218eF2e820987c59F838906A82455F42D98b",
  oneInchV4RouterAddress: polygonChainData.oneinch.v4Router,
  oneInchV5RouterAddress: polygonChainData.oneinch.v5Router,
  uniV3: {
    uniswapV3RouterAddress: uniswapV3.router,
    uniSwapV3NonfungiblePositionManagerAddress: uniswapV3.nonfungiblePositionManager,
    uniswapV3FactoryAddress: uniswapV3.factory,
  },

  // Arakis V1 contract addresses
  arrakisV1: {
    arrakisV1RouterStakingAddress: polygonChainData.arrakis.v1RouterStaking,
  },

  // Token Addresses
  sushiTokenAddress: "0x0b3f868e0be5597d5db7feb59e1cadbb0fdda50a",
  wmaticTokenAddress: "0x0d500b1d8e8ef31e21c99d1db9a6444d3adf1270",

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
};

export const polygonProdAddresses: IAddresses = {
  ...polygonAddresses,
  stakingV2: {
    emissionsRate: 1000,
    dhtCap: BigNumber.from(2_000_000).mul(BigNumber.from(10).pow(18)),
    whitelistedPools: [
      // Polygon	Test Pool	https://app.dhedge.org/vault/0x5e0775919ee36e3e956622c01b8e8b64bd8eb7c5	$1,000
      { pool: "0x5e0775919ee36e3e956622c01b8e8b64bd8eb7c5", cap: BigNumber.from(1000).mul(BigNumber.from(10).pow(18)) },
    ],
  },
};

export const polygonStagingAddresses: IAddresses = {
  ...polygonAddresses,
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
