import { dhedgeEasySwapperAddress } from "../../config/chainData/polygon-data";
import { IAddresses, IFileNames } from "../types";
import fs from "fs";

// Openzepplin doesn't support having two distinct deployments of the same contracts to the same chain.
// Itt always looks for the file "unknown-137.json" (137 is the chainId).
// To be able to have two distinct deployments we switch files in and out as "unknown-137.json" depending on where we targeting to deploy
export const switchPolygonOzFile = (isProduction: boolean) => {
  console.log("Switching Polygon Openzepplin files.");
  const ozPath = "./.openzeppelin/";
  const ozEnvFile = ozPath + (isProduction ? "polygon-production.json" : "polygon-staging.json");
  const ozExpectedFile = ozPath + "unknown-137.json";
  fs.renameSync(ozEnvFile, ozExpectedFile);

  process.on("SIGINT", () => {
    console.log("Process Interrupted, Reverting rename");
    if (fs.existsSync(ozExpectedFile)) {
      fs.renameSync(ozExpectedFile, ozEnvFile);
    }
    console.log("Exiting...");
    // eventually exit
    process.exit(); // Add code if necessary
  });

  process.on("exit", () => {
    console.log("Process Interrupted, Reverting rename");
    if (fs.existsSync(ozExpectedFile)) {
      fs.renameSync(ozExpectedFile, ozEnvFile);
    }
    console.log("Exiting...");
    // eventually exit
    process.exit(); // Add code if necessary
  });
};

export const polygonAddresses: IAddresses = {
  // Dhedge Internal
  protocolDaoAddress: "0xc715Aa67866A2FEF297B12Cb26E953481AeD2df4",
  protocolTreasuryAddress: "0x6f005cbceC52FFb28aF046Fd48CB8D6d19FD25E3",
  // Should be fetched from the oz file
  proxyAdminAddress: "0x0C0a10C9785a73018077dBC74B2A006695849252",
  // Same for everyone
  implementationStorageAddress: "0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc",
  // Gnosis safe multicall/send address
  // https://github.com/gnosis/safe-deployments
  gnosisMultiSendAddress: "0xA238CBeb142c10Ef7Ad8442C6D1f9E89e07e7761",
  gnosisApi: "https://safe-transaction.polygon.gnosis.io",

  dhedgeEasySwapperAddress: dhedgeEasySwapperAddress,

  // External Logic Contracts
  balancerV2VaultAddress: "0xBA12222222228d8Ba445958a75a0704d566BF2C8",
  balancerMerkleOrchardAddress: "0x0F3e0c4218b7b0108a3643cFe9D3ec0d4F57c54e",
  sushiMiniChefV2Address: "0x0769fd68dFb93167989C6f7254cd0D766Fb2841F",
  aaveProtocolDataProviderAddress: "0x7551b5D2763519d4e37e8B81929D336De671d46d",
  aaveIncentivesControllerAddress: "0x357D51124f59836DeD84c8a1730D72B749d8BC23",
  aaveLendingPoolAddress: "0x8dFf5E27EA6b7AC08EbFdf9eB090F32ee9a30fcf",

  quickStakingRewardsFactoryAddress: "0x5eec262B05A57da9beb5FE96a34aa4eD0C5e029f",
  v2RouterAddresses: ["0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506", "0xa5E0829CaCEd8fFDD4De3c43696c57F7D7A678ff"], //quickswapRouter, sushiswapV2Router etc etc
  quickLpUsdcWethStakingRewardsAddress: "0x4A73218eF2e820987c59F838906A82455F42D98b",
  oneInchV4RouterAddress: "0x1111111254fb6c44bac0bed2854e76f90643097d",

  // Token Addresses
  sushiTokenAddress: "0x0b3f868e0be5597d5db7feb59e1cadbb0fdda50a",
  wmaticTokenAddress: "0x0d500b1d8e8ef31e21c99d1db9a6444d3adf1270",
};

export const polygonStagingFileNames: IFileNames = {
  versionsFileName: "./publish/polygon/staging/versions.json",
  assetsFileName: "./config/polygon-staging/dHEDGE Assets list - Polygon Staging.csv",
  governanceNamesFileName: "./config/polygon-staging/dHEDGE Governance Names - Polygon Staging.csv",
  contractGuardsFileName: "./config/polygon-staging/dHEDGE Governance Contract Guards - Polygon Staging.csv",
  assetGuardsFileName: "./config/polygon-staging/dHEDGE Governance Asset Guards - Polygon Staging.csv",
  balancerConfigFileName: "./config/polygon-staging/dHEDGE Asset list - Polygon Balancer LP Staging.json",
  externalAssetFileName: "./config/polygon-staging/dHEDGE Assets list - Polygon External Staging.csv",
};

export const polygonProdFileNames: IFileNames = {
  versionsFileName: "./publish/polygon/prod/versions.json",
  assetsFileName: "./config/polygon-prod/dHEDGE Assets list - Polygon.csv",
  governanceNamesFileName: "./config/polygon-prod/dHEDGE Governance Names - Polygon.csv",
  contractGuardsFileName: "./config/polygon-prod/dHEDGE Governance Contract Guards - Polygon.csv",
  assetGuardsFileName: "./config/polygon-prod/dHEDGE Governance Asset Guards - Polygon.csv",
  balancerConfigFileName: "./config/polygon-prod/dHEDGE Asset list - Polygon Balancer LP.json",
  externalAssetFileName: "./config/polygon-prod/dHEDGE Assets list - Polygon External.csv",
};
