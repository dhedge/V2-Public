import { task, types } from "hardhat/config";
import fs from "fs";
import { assets, quickswap, protocolDao, sushi, torosPools } from "../../config/chainData/polygon-data";

import { tryVerify } from "../Helpers";
import { getDeploymentData } from "../upgrade/getDeploymentData";
import { IVersions } from "../types";

task("easySwapper", "dHEDGE Easy Swapper commands")
  .addOptionalParam("production", "run in production environment", false, types.boolean)
  .addOptionalParam("execute", "deploy easySwapper", false, types.boolean)
  .setAction(async (taskArgs, hre) => {
    const ethers = hre.ethers;
    const network = await ethers.provider.getNetwork();
    console.log("Network:", network.name);

    if (taskArgs.execute) {
      const deploymentData = getDeploymentData(network.chainId, taskArgs.production ? "production" : "staging");
      const versions: IVersions = JSON.parse(fs.readFileSync(deploymentData.filenames.versionsFileName, "utf-8"));
      const latestVersion = Object.keys(versions)[Object.keys(versions).length - 1];
      let versionUpdate = false;

      // if (versions[latestVersion].contracts.DhedgeEasySwapper) {
      //   throw new Error("Easy Swapper contract already deployed");
      // }

      const DhedgeEasySwapper = await ethers.getContractFactory("DhedgeEasySwapper");
      const dhedgeEasySwapper = await DhedgeEasySwapper.deploy(
        protocolDao,
        {
          swapRouter: versions[latestVersion].contracts.DhedgeSwapRouter,
          weth: assets.weth,
          assetType2Router: sushi.router,
          assetType5Router: quickswap.router,
        },
        versions[latestVersion].contracts.PoolFactoryProxy,
      ); // Init version

      await dhedgeEasySwapper.deployed();

      // Enable the Toros leverage pools (Production)
      for (const leveragePool of Object.values(torosPools)) {
        await dhedgeEasySwapper.setPoolAllowed(leveragePool, true);
      }
      await dhedgeEasySwapper.setPoolAllowed(assets.dusd, true);

      await dhedgeEasySwapper.transferOwnership(protocolDao);

      versions[latestVersion].contracts.DhedgeEasySwapper = dhedgeEasySwapper.address;
      versionUpdate = true;

      console.log("DhedgeEasySwapper deployed to: ", dhedgeEasySwapper.address);
      await tryVerify(hre, dhedgeEasySwapper.address, "contracts/EasySwapper/DhedgeEasySwapper.sol:DhedgeEasySwapper", [
        protocolDao,
        {
          swapRouter: quickswap.router,
          weth: assets.weth,
          assetType2Router: sushi.router,
          assetType5Router: quickswap.router,
        },
        versions[latestVersion].contracts.PoolFactoryProxy,
      ]);
      if (versionUpdate) {
        versions[latestVersion].lastUpdated = new Date().toUTCString();
        // convert JSON object to string
        const data = JSON.stringify(versions, null, 2);
        // write to version file
        fs.writeFileSync(deploymentData.filenames.versionsFileName, data);
      }
    }
  });
