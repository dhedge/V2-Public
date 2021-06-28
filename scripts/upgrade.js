const fs = require("fs");
const { getTag } = require("./Helpers");

task("upgrade", "Upgrade proxy contracts")
  .addOptionalParam("poolFactory", "upgrade poolFactory", false, types.boolean)
  .addOptionalParam("assetHandler", "upgrade assetHandler", false, types.boolean)
  .addOptionalParam("poolLogic", "upgrade poolLogic", false, types.boolean)
  .addOptionalParam("poolManagerLogic", "upgrade poolManagerLogic", false, types.boolean)
  .setAction(async taskArgs => {
    let network = await ethers.provider.getNetwork();
    console.log("network:", network);
    const hre = require("hardhat");
    let networks = hre.config.networks;
    networkNames = Object.keys(networks);
    networkNames.map((name) => {
      if(networks[name].chainId === network.chainId){
        network.name = name;
      }
    })
    let versions = require(`../publish/${network.name}/versions.json`);
    let newTag = await getTag();
    let oldTag = Object.keys(versions)[Object.keys(versions).length - 1];
    if (newTag == oldTag) throw("Error: No new version to upgrade");

    let contracts = versions[oldTag].contracts;
    versions[newTag] = new Object;
    versions[newTag].contracts = contracts;
    versions[newTag].network = network;
    versions[newTag].date = new Date().toUTCString();

    if(taskArgs.poolFactory){
      // For testing
      // const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";
      // const PoolFactory = await ethers.getContractFactory("PoolFactory");
      // const poolFactoryProxy = await upgrades.deployProxy(PoolFactory, [
      //   contracts.PoolLogicProxy,
      //   contracts.PoolManagerLogicProxy,
      //   ZERO_ADDRESS,
      //   ZERO_ADDRESS,
      // ]);
      // console.log("poolFactory deployed at: ", poolFactoryProxy.address);
      // const poolFactory = await upgrades.upgradeProxy(poolFactoryProxy.address, PoolFactory);

      let oldPoolFactory = contracts.PoolFactoryProxy;
      const PoolFactory = await ethers.getContractFactory("PoolFactory");
      const poolFactory = await upgrades.upgradeProxy(oldPoolFactory, PoolFactory);
      console.log("poolFactory upgraded to: ", poolFactory.address);
      versions[newTag].contracts.PoolFactoryProxy = poolFactory.address;
    }
    if(taskArgs.assetHandler){
      let oldAssetHandler = contracts.AssetHandlerProxy;
      const AssetHandler = await ethers.getContractFactory("AssetHandler");
      const assetHandler = await upgrades.upgradeProxy(oldAssetHandler, AssetHandler);
      console.log("assetHandler upgraded to: ", assetHandler.address);
      versions[newTag].contracts.AssetHandlerProxy = assetHandler.address;
    }
    if(taskArgs.poolLogic){
      let oldPoolLogic = contracts.PoolLogicProxy;
      const PoolLogic = await ethers.getContractFactory("PoolLogic");
      const poolLogic = await upgrades.upgradeProxy(oldPoolLogic, PoolLogic);
      console.log("poolLogic upgraded to: ", poolLogic.address);
      versions[newTag].contracts.PoolLogicProxy = poolLogic.address;
    }
    if(taskArgs.poolManagerLogic){
      let oldPoolManagerLogic = contracts.PoolManagerLogicProxy;
      const PoolManagerLogic = await ethers.getContractFactory("PoolManagerLogic");
      const poolManagerLogic = await upgrades.upgradeProxy(oldPoolManagerLogic, PoolManagerLogic);
      console.log("poolManagerLogic upgraded to: ", poolManagerLogic.address);
      versions[newTag].contracts.PoolManagerLogicProxy = poolManagerLogic.address;
    }

    // convert JSON object to string
    const data = JSON.stringify(versions, null, 2);
    console.log(data);

    fs.writeFileSync(`./publish/${network.name}/versions.json`, data);
  });

module.exports = {};