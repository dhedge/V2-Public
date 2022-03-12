import { task, types } from "hardhat/config";
import fs from "fs";

import { deployUniV2TwapOracle } from "./deployUniV2TwapOracle";
import { getDeploymentData } from "../upgrade/getDeploymentData";
import { IVersions } from "../types";

export interface IAssetOracle {
  name: string;
  assetAddress: string;
  poolAddress: string;
  pairTokenOracle: string;
  poolType: string;
  updateInterval?: number;
  volatilityTripLimit?: number;
}

task("deployAssetOracles", "Deploy pending asset/TWAP oracles as per ./config")
  .addOptionalParam("execute", "propose transactions", false, types.boolean)
  .addOptionalParam("production", "run in production environment", false, types.boolean)
  .setAction(async (taskArgs, hre) => {
    const ethers = hre.ethers;
    const upgrades = hre.upgrades;
    const network = await ethers.provider.getNetwork();
    console.log("Network:", network.name);
    await hre.run("compile");

    const deploymentData = getDeploymentData(network.chainId, taskArgs.production ? "production" : "staging");

    // Init version
    const versions: IVersions = JSON.parse(fs.readFileSync(deploymentData.filenames.versionsFileName, "utf-8"));
    if (!versions) throw new Error("No versions file");
    const latestVersion = Object.keys(versions)[Object.keys(versions).length - 1];
    const version = versions[latestVersion];

    // Init version
    const oracles: IAssetOracle[] = deploymentData.filenames.assetOracleConfigFileName
      ? JSON.parse(fs.readFileSync(deploymentData.filenames.assetOracleConfigFileName!, "utf-8"))
      : [];
    let versionUpdate = false;

    for (const oracle of oracles) {
      const foundInVersions = version.contracts.Oracles?.some(
        (x) => oracle.assetAddress.toLowerCase() == x.assetAddress.toLowerCase(),
      );

      if (!foundInVersions) {
        console.log(`Will deploy asset oracle for ${oracle.name}`);
        if (taskArgs.execute) {
          // Deploy any Uniswap V2 TWAP asset oracles
          if (oracle.poolType === "UniswapV2") {
            const oracleData = await deployUniV2TwapOracle(hre, oracle);
            versions[latestVersion].contracts.Oracles!.push(oracleData);
            versionUpdate = true;
          }
        }
      }
    }

    if (versionUpdate) {
      versions[latestVersion].lastUpdated = new Date().toUTCString();
      // convert JSON object to string
      const data = JSON.stringify(versions, null, 2);
      // write to version file
      fs.writeFileSync(deploymentData.filenames.versionsFileName, data);
    }
  });
