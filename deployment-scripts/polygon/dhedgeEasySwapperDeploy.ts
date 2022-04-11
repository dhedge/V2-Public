import { task, types } from "hardhat/config";
import fs from "fs";
import { assets, quickswap, protocolDao, sushi } from "../../config/chainData/polygon-data";

import { proposeTx, tryVerify } from "../Helpers";
import { getDeploymentData } from "../upgrade/getDeploymentData";
import { IVersions } from "../types";

task("easySwapper", "dHEDGE Easy Swapper commands")
  .addOptionalParam("production", "run in production environment", false, types.boolean)
  .addOptionalParam("execute", "deploy easySwapper", false, types.boolean)
  .setAction(async (taskArgs, hre) => {
    const ethers = hre.ethers;
    const network = await ethers.provider.getNetwork();
    console.log("Network:", network.name);
    console.log("Will deploy easySwapper");
    if (taskArgs.execute) {
      const deploymentData = getDeploymentData(network.chainId, taskArgs.production ? "production" : "staging");
      const versions: IVersions = JSON.parse(fs.readFileSync(deploymentData.filenames.versionsFileName, "utf-8"));
      const latestVersion = Object.keys(versions)[Object.keys(versions).length - 1];

      if (!deploymentData.addresses.torosEasySwapperAllowedPools) {
        throw new Error("torosEasySwapperAllowedPools not defined");
      }

      const DhedgeEasySwapper = await ethers.getContractFactory("DhedgeEasySwapper");
      const dhedgeEasySwapper = await DhedgeEasySwapper.deploy(protocolDao, {
        swapRouter: versions[latestVersion].contracts.DhedgeSwapRouter,
        weth: assets.weth,
        assetType2Router: sushi.router,
        assetType5Router: quickswap.router,
        poolFactory: versions[latestVersion].contracts.PoolFactoryProxy,
      }); // Init version

      await dhedgeEasySwapper.deployed();

      // Enable the Toros leverage pools (Production)
      // This should not contain non leveraged pools
      for (const leveragePool of deploymentData.addresses.torosEasySwapperAllowedPools) {
        await dhedgeEasySwapper.setPoolAllowed(leveragePool, true);
      }

      await dhedgeEasySwapper.transferOwnership(protocolDao);

      versions[latestVersion].contracts.DhedgeEasySwapper = dhedgeEasySwapper.address;

      console.log("DhedgeEasySwapper deployed to: ", dhedgeEasySwapper.address);
      await tryVerify(hre, dhedgeEasySwapper.address, "contracts/EasySwapper/DhedgeEasySwapper.sol:DhedgeEasySwapper", [
        protocolDao,
        {
          swapRouter: versions[latestVersion].contracts.DhedgeSwapRouter,
          weth: assets.weth,
          assetType2Router: sushi.router,
          assetType5Router: quickswap.router,
          poolFactory: versions[latestVersion].contracts.PoolFactoryProxy,
        },
      ]);

      const poolFactoryProxy = versions[latestVersion].contracts.PoolFactoryProxy;
      const PoolFactory = await hre.artifacts.readArtifact("PoolFactory");
      const PoolFactoryABI = new ethers.utils.Interface(PoolFactory.abi);

      versions[latestVersion].lastUpdated = new Date().toUTCString();
      // convert JSON object to string
      const data = JSON.stringify(versions, null, 2);
      // write to version file
      fs.writeFileSync(deploymentData.filenames.versionsFileName, data);

      try {
        const addTransferWhitelistABI = PoolFactoryABI.encodeFunctionData("addTransferWhitelist", [
          dhedgeEasySwapper.address,
        ]);

        await proposeTx(
          poolFactoryProxy,
          addTransferWhitelistABI,
          "Add new easy swapper to whitelist",
          { execute: true, restartnonce: false },
          deploymentData.addresses,
        );
      } catch {
        console.log("Deployed successfully, but unable to propose whitelist tx");
      }
    }
  });
