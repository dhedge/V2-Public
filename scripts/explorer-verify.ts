import { task, types } from "hardhat/config";

const { getTag, tryVerify } = require("./Helpers");

task("explorerVerify", "Verify contracts")
  .addOptionalParam("production", "run in production environment", false, types.boolean)
  .setAction(async (taskArgs) => {
    const hre = require("hardhat");
    let versionsFilePath;

    switch (hre.network.name) {
      case "ovm":
        versionsFilePath = `../publish/ovm/prod/versions.json`;
        break;
      default:
        throw new Error("No Versions file configured");
    }

    const versions = require(versionsFilePath);
    const currentTag = await getTag();
    console.log("currentTag:", currentTag);
    const contracts = versions[currentTag].contracts;
    const provider = hre.ethers.provider;

    const implementationStorage = "0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc";

    if (contracts.Governance) {
      await tryVerify(hre, contracts.Governance, "contracts/Governance.sol:Governance", []);
    }

    if (contracts.PoolFactory && contracts.PoolFactory.proxy) {
      const implementation = await provider.getStorageAt(contracts.PoolFactory.proxy, implementationStorage);
      const address = hre.ethers.utils.hexValue(implementation);
      console.log("PoolFactory: ", address);
      await tryVerify(hre, contracts.PoolFactory.implementation, "contracts/PoolFactory.sol:PoolFactory", []);
    }

    if (contracts.PoolLogic) {
      await tryVerify(hre, contracts.PoolLogic.implementation, "contracts/PoolLogic.sol:PoolLogic", []);
    }

    if (contracts.PoolManagerLogic) {
      await tryVerify(
        hre,
        contracts.PoolManagerLogic.implementation,
        "contracts/PoolManagerLogic.sol:PoolManagerLogic",
        [],
      );
    }

    if (contracts.AssetHandler && contracts.AssetHandler.proxy) {
      const implementation = await provider.getStorageAt(contracts.AssetHandler.proxy, implementationStorage);
      const address = hre.ethers.utils.hexValue(implementation);
      console.log("AssetHandler: ", address);
      await tryVerify(hre, address, "contracts/assets/AssetHandler.sol:AssetHandler", []);
    }

    if (contracts.ERC20Guard) {
      await tryVerify(hre, contracts.ERC20Guard, "contracts/guards/assetGuards/ERC20Guard.sol:ERC20Guard");
    }

    if (contracts.PoolPerformance && contracts.PoolPerformance.proxy) {
      const implementation = await provider.getStorageAt(contracts.PoolPerformance.proxy, implementationStorage);
      const address = hre.ethers.utils.hexValue(implementation);
      console.log("PoolPerformance: ", address);
      await tryVerify(hre, address, "contracts/PoolPerformance.sol:PoolPerformance", []);
    }
  });

module.exports = {};
