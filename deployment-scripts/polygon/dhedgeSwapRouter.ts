import fs from "fs";
import { task, types } from "hardhat/config";
import { tryVerify } from "../Helpers";
import { IVersions } from "../types";
import { getDeploymentData } from "../upgrade/getDeploymentData";

task("swapRouter", "dHEDGE Easy Swapper commands")
  .addOptionalParam("production", "run in production environment", false, types.boolean)
  .addOptionalParam("execute", "deploy swapRouter", false, types.boolean)
  .setAction(async (taskArgs, hre) => {
    const ethers = hre.ethers;
    const network = await ethers.provider.getNetwork();
    console.log("Network:", network.name);

    // Init version
    const deploymentData = getDeploymentData(network.chainId, taskArgs.production ? "production" : "staging");
    const versions: IVersions = JSON.parse(fs.readFileSync(deploymentData.filenames.versionsFileName, "utf-8"));
    const latestVersion = Object.keys(versions)[Object.keys(versions).length - 1];
    let versionUpdate = false;

    console.log("Will deploy swapRouter");
    if (taskArgs.execute) {
      if (versions[latestVersion].contracts.DhedgeSwapRouter) throw "DhedgeSwapRouter contract already deployed";

      const DhedgeSwapRouter = await ethers.getContractFactory("DhedgeSwapRouter");
      console.log(
        "Deploying SwapRouter with",
        deploymentData.addresses.v2RouterAddresses || [],
        deploymentData.addresses.swapRouterCurvePools || [],
      );
      const dhedgeSwapRouter = await DhedgeSwapRouter.deploy(
        deploymentData.addresses.v2RouterAddresses || [],
        deploymentData.addresses.swapRouterCurvePools || [],
      );
      await dhedgeSwapRouter.deployed();

      console.log("DhedgeSwapRouter deployed to: ", dhedgeSwapRouter.address);
      await tryVerify(hre, dhedgeSwapRouter.address, "contracts/DhedgeSwapRouter.sol:DhedgeSwapRouter", [
        deploymentData.addresses.v2RouterAddresses || [],
        deploymentData.addresses.swapRouterCurvePools || [],
      ]);

      versions[latestVersion].contracts.DhedgeSwapRouter = dhedgeSwapRouter.address;
      versionUpdate = true;
    }

    if (versionUpdate) {
      versions[latestVersion].lastUpdated = new Date().toUTCString();
      // convert JSON object to string
      const data = JSON.stringify(versions, null, 2);
      // write to version file
      fs.writeFileSync(deploymentData.filenames.versionsFileName, data);
    }
  });
