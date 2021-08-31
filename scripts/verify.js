const { ethers } = require("hardhat");
const hre = require("hardhat");
const csv = require("csvtojson");
const { getTag, tryVerify } = require("./Helpers");
const stagingExternalAssetFileName = "./config/staging/dHEDGE Assets list - Polygon External Staging.csv";
const prodExternalAssetFileName = "./config/prod/dHEDGE Assets list - Polygon External.csv";
const env = process.env.NODE_ENV;

async function main() {
  const network = await ethers.provider.getNetwork();
  console.log("network:", network);
  const versionFile = env == "production" ? "versions" : "staging-versions";
  const versions = require(`../publish/${network.name}/${versionFile}.json`);
  const currentTag = await getTag();
  console.log("currentTag:", currentTag);
  const contracts = versions[currentTag].contracts;
  const provider = ethers.provider;
  const implementationStorage = "0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc";

  if (contracts.Governance) {
    tryVerify(hre, contracts.Governance, "contracts/guards/assetGuards/OpenAssetGuard.sol:OpenAssetGuard", []);
  }
  if (contracts.PoolFactoryProxy) {
    const implementation = await provider.getStorageAt(contracts.PoolFactoryProxy, implementationStorage);
    tryVerify(hre, ethers.utils.hexValue(implementation), "contracts/PoolFactory.sol:PoolFactory", []);
  }
  if (contracts.PoolLogic) {
    tryVerify(hre, contracts.PoolLogic, "contracts/PoolLogic.sol:PoolLogic", []);
  }
  if (contracts.PoolManagerLogic) {
    tryVerify(hre, contracts.PoolManagerLogic, "contracts/PoolManagerLogic.sol:PoolManagerLogic", []);
  }
  if (contracts.AssetHandlerProxy) {
    const implementation = await provider.getStorageAt(contracts.AssetHandlerProxy, implementationStorage);
    tryVerify(hre, ethers.utils.hexValue(implementation), "contracts/assets/AssetHandler.sol:AssetHandler", []);
  }
  if (contracts.OpenAssetGuard) {
    const fileName = env == "production" ? prodExternalAssetFileName : stagingExternalAssetFileName;
    const csvAssets = await csv().fromFile(fileName);
    let addresses = csvAssets.map((asset) => asset.Address);
    addresses = typeof addresses === "string" ? [addresses] : addresses;
    tryVerify(
      hre,
      contracts.OpenAssetGuard,
      "contracts/guards/assetGuards/OpenAssetGuard.sol:OpenAssetGuard",
      addresses,
    );
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
