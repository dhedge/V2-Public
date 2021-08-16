const { ethers } = require("hardhat");
const hre = require("hardhat");
const { getTag } = require("./Helpers");

async function main() {
  const network = await ethers.provider.getNetwork();
  console.log("network:", network);
  const versions = require(`../publish/${network.name}/versions.json`);
  const currentTag = await getTag();
  console.log("currentTag:", currentTag);
  const contracts = versions[currentTag].contracts;
  const provider = ethers.provider;
  const implementationStorage = "0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc";

  if(contracts.Governance){
    await hre.run("verify:verify", {
      address: contracts.Governance,
      contract: "contracts/Governance.sol:Governance",
    });
  }
  if(contracts.PoolFactoryProxy){
    const implementation = await provider.getStorageAt(contracts.PoolFactoryProxy, implementationStorage)
    await hre.run("verify:verify", {
      address: ethers.utils.hexValue(implementation),
      contract: "contracts/PoolFactory.sol:PoolFactory",
    });
  }
  if(contracts.PoolLogic){
    await hre.run("verify:verify", {
      address: contracts.PoolLogic,
      contract: "contracts/PoolLogic.sol:PoolLogic",
    });
  }
  if(contracts.PoolManagerLogic){
    await hre.run("verify:verify", {
      address: contracts.PoolManagerLogic,
      contract: "contracts/PoolManagerLogic.sol:PoolManagerLogic",
    });
  }
  if(contracts.AssetHandlerProxy){
    const implementation = await provider.getStorageAt(contracts.AssetHandlerProxy, implementationStorage)
    await hre.run("verify:verify", {
      address: ethers.utils.hexValue(implementation),
      contract: "contracts/assets/AssetHandler.sol:AssetHandler",
    });
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });