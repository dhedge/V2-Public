import { task, types } from "hardhat/config";
import fs from "fs";
import { assets, quickswap, protocolDao, aave, toros } from "../../config/chainData/polygon-data";

import { tryVerify } from "../Helpers";
const torosLeveragePools = toros.leveragePools;

task("easySwapper", "dHEDGE Easy Swapper commands")
  .addOptionalParam("production", "run in production environment", false, types.boolean)
  .addOptionalParam("deploy", "deploy Dynamic Bonds", false, types.boolean)
  .setAction(async (taskArgs, hre) => {
    const ethers = hre.ethers;
    const network = await ethers.provider.getNetwork();
    console.log("Network:", network.name);

    // Init version
    const versionFile = taskArgs.production ? "versions" : "staging-versions";
    const versionPath = `../publish/${network.name}/${versionFile}.json`;
    const versions = require(versionPath);
    const latestVersion = Object.keys(versions)[Object.keys(versions).length - 1];
    let versionUpdate = false;

    if (taskArgs.deploy) {
      if (versions[latestVersion].contracts.DhedgeEasySwapper) throw "Easy Swapper contract already deployed";

      const DhedgeEasySwapper = await ethers.getContractFactory("DhedgeEasySwapper");
      const dhedgeEasySwapper = await DhedgeEasySwapper.deploy(protocolDao, quickswap.router, assets.weth);
      await dhedgeEasySwapper.deployed();

      console.log("DhedgeEasySwapper deployed to: ", dhedgeEasySwapper.address);
      await tryVerify(hre, dhedgeEasySwapper.address, "contracts/DhedgeEasySwapper.sol:DhedgeEasySwapper", [
        quickswap.router,
        assets.weth,
      ]);

      await dhedgeEasySwapper.setAssetToSkip(aave.lendingPool, true); // Aave is processed separately
      // Enable the Toros leverage pools (Production)
      for (const leveragePool of torosLeveragePools) {
        await dhedgeEasySwapper.setPoolAllowed(leveragePool, true);
      }

      await dhedgeEasySwapper.transferOwnership(protocolDao);

      versions[latestVersion].contracts.DhedgeEasySwapper = dhedgeEasySwapper.address;
      versionUpdate = true;
    }

    if (versionUpdate) {
      versions[latestVersion].date = new Date().toUTCString();
      // convert JSON object to string
      const data = JSON.stringify(versions, null, 2);
      // write to version file
      fs.writeFileSync(`./publish/${network.name}/${versionFile}.json`, data);
    }
  });
