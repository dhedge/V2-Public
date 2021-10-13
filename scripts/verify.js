const csv = require("csvtojson");
const { getTag, tryVerify } = require("./Helpers");
const stagingExternalAssetFileName = "./config/staging/dHEDGE Assets list - Polygon External Staging.csv";
const prodExternalAssetFileName = "./config/prod/dHEDGE Assets list - Polygon External.csv";

task("verify", "Verify contracts")
  .addOptionalParam("production", "run in production environment", false, types.boolean)
  .setAction(async (taskArgs) => {
    const hre = require("hardhat");
    const network = await ethers.provider.getNetwork();
    console.log("network:", network);
    const versionFile = taskArgs.production ? "versions" : "staging-versions";
    const versions = require(`../publish/${network.name}/${versionFile}.json`);
    const currentTag = await getTag();
    console.log("currentTag:", currentTag);
    const contracts = versions[currentTag].contracts;
    const provider = ethers.provider;
    const implementationStorage = "0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc";

    if (contracts.Governance) {
      await tryVerify(hre, contracts.Governance, "contracts/Governance.sol:Governance", []);
    }
    if (contracts.PoolFactoryProxy) {
      const implementation = await provider.getStorageAt(contracts.PoolFactoryProxy, implementationStorage);
      const address = ethers.utils.hexValue(implementation);
      console.log("PoolFactory: ", address);
      await tryVerify(hre, address, "contracts/PoolFactory.sol:PoolFactory", []);
    }
    if (contracts.PoolLogic) {
      await tryVerify(hre, contracts.PoolLogic, "contracts/PoolLogic.sol:PoolLogic", []);
    }
    if (contracts.PoolManagerLogic) {
      await tryVerify(hre, contracts.PoolManagerLogic, "contracts/PoolManagerLogic.sol:PoolManagerLogic", []);
    }
    if (contracts.AssetHandlerProxy) {
      const implementation = await provider.getStorageAt(contracts.AssetHandlerProxy, implementationStorage);
      const address = ethers.utils.hexValue(implementation);
      console.log("AssetHandler: ", address);
      await tryVerify(hre, address, "contracts/assets/AssetHandler.sol:AssetHandler", []);
    }
    if (contracts.OpenAssetGuard) {
      const fileName = taskArgs.production ? prodExternalAssetFileName : stagingExternalAssetFileName;
      const csvAssets = await csv().fromFile(fileName);
      let addresses = csvAssets.map((asset) => asset.Address);
      await tryVerify(hre, contracts.OpenAssetGuard, "contracts/guards/assetGuards/OpenAssetGuard.sol:OpenAssetGuard", [
        addresses,
      ]);
    }
    if (contracts.PoolPerformanceProxy) {
      const implementation = await provider.getStorageAt(contracts.PoolPerformanceProxy, implementationStorage);
      const address = ethers.utils.hexValue(implementation);
      console.log("PoolPerformance: ", address);
      await tryVerify(hre, address, "contracts/PoolPerformance.sol:PoolPerformance", []);
    }
  });

module.exports = {};
