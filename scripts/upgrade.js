const fs = require("fs");
const { getTag } = require("./Helpers");
const Safe = require("@gnosis.pm/safe-core-sdk");
const { EthersAdapter } = require('@gnosis.pm/safe-core-sdk');
const { SafeService } = require("@gnosis.pm/safe-ethers-adapters");
const proxyAdminAddress = "0x0C0a10C9785a73018077dBC74B2A006695849252";
const safeAddress = "0xc715Aa67866A2FEF297B12Cb26E953481AeD2df4";
// https://github.com/gnosis/safe-deployments/blob/main/src/assets/v1.3.0/multi_send.json#L13
const multiSendAddress = "0xA238CBeb142c10Ef7Ad8442C6D1f9E89e07e7761";
const service = new SafeService("https://safe-transaction.polygon.gnosis.io");

task("upgrade", "Upgrade proxy contracts")
  .addOptionalParam("poolFactory", "upgrade poolFactory", false, types.boolean)
  .addOptionalParam("assetHandler", "upgrade assetHandler", false, types.boolean)
  .addOptionalParam("poolLogic", "upgrade poolLogic", false, types.boolean)
  .addOptionalParam("poolManagerLogic", "upgrade poolManagerLogic", false, types.boolean)
  .setAction(async taskArgs => {

    const provider = ethers.provider;
    const owner1 = provider.getSigner(0);
    const ethAdapter = new EthersAdapter({ ethers: ethers, signer: owner1 });
    const chainId = await ethAdapter.getChainId();

    const contractNetworks = {
      [chainId]: {
        multiSendAddress: multiSendAddress,
      }
    }

    // I'm having Safe.create is not a function issue
    const safeSdk = await Safe.default.create({
      ethAdapter,
      safeAddress: safeAddress,
      contractNetworks
    });

    owner1Address = await owner1.getAddress();

    let network = await ethers.provider.getNetwork();
    console.log("network:", network);

    const hre = require("hardhat");
    let networks = hre.config.networks;
    networkNames = Object.keys(networks);
    let versions = require(`../publish/${network.name}/versions.json`);
    let newTag = await getTag();
    let oldTag = Object.keys(versions)[Object.keys(versions).length - 1];
    console.log(`oldTag: ${oldTag}`);
    console.log(`newTag: ${newTag}`);
    if (newTag == oldTag) throw("Error: No new version to upgrade");

    let contracts = versions[oldTag].contracts;
    versions[newTag] = new Object;
    versions[newTag].contracts = { ...contracts };
    versions[newTag].network = network;
    versions[newTag].date = new Date().toUTCString();
    const PoolFactory = await ethers.getContractFactory("PoolFactory");
    let setLogic = false;

    if(taskArgs.poolFactory){
      let poolFactoryProxy = contracts.PoolFactoryProxy;
      const newPoolFactoryLogic = await upgrades.prepareUpgrade(poolFactoryProxy, PoolFactory);
      console.log("New PoolFactory logic deployed to: ", newPoolFactoryLogic);

      const ProxyAdmin = await hre.artifacts.readArtifact("ProxyAdmin");
      const proxyAdmin = new ethers.utils.Interface(ProxyAdmin.abi);
      const upgradeABI = proxyAdmin.encodeFunctionData("upgrade", [poolFactoryProxy, newPoolFactoryLogic]);

      const transaction = {
        to: proxyAdminAddress,
        value: "0",
        data: upgradeABI,
      }

      const safeTransaction = await safeSdk.createTransaction(...[transaction])
      // off-chain sign
      const txHash = await safeSdk.getTransactionHash(safeTransaction);
      const signature = await safeSdk.signTransactionHash(txHash);
      // on-chain sign
      // const approveTxResponse = await safeSdk.approveTransactionHash(txHash)
      // console.log("approveTxResponse", approveTxResponse);
      console.log("safeTransaction: ", safeTransaction);

      const proposeTx = await service.proposeTx(safeAddress, txHash, safeTransaction, signature)
      console.log("ProposeTx: ", proposeTx);
    }
    if(taskArgs.assetHandler){
      let oldAssetHandler = contracts.AssetHandlerProxy;
      const AssetHandler = await ethers.getContractFactory("AssetHandler");
      const assetHandler = await upgrades.upgradeProxy(oldAssetHandler, AssetHandler);
      console.log("assetHandler upgraded to: ", assetHandler.address);
    }
    if(taskArgs.poolLogic){
      const PoolLogic = await ethers.getContractFactory("PoolLogic");
      let poolLogic = await PoolLogic.deploy();
      console.log("poolLogic upgraded to: ", poolLogic.address);
      versions[newTag].contracts.PoolLogic = poolLogic.address;
      setLogic = true;
    }
    if(taskArgs.poolManagerLogic){
      const PoolManagerLogic = await ethers.getContractFactory("PoolManagerLogic");
      const poolManagerLogic = await PoolManagerLogic.deploy();
      console.log("poolManagerLogic upgraded to: ", poolManagerLogic.address);
      versions[newTag].contracts.PoolManagerLogic = poolManagerLogic.address;
      setLogic = true;
    }
    if(setLogic){
      let poolFactory = await PoolFactory.attach(versions[newTag].contracts.PoolFactoryProxy);
      await poolFactory.setLogic(versions[newTag].contracts.PoolLogic, versions[newTag].contracts.PoolManagerLogic);
    }

    // convert JSON object to string
    const data = JSON.stringify(versions, null, 2);
    console.log(data);

    fs.writeFileSync(`./publish/${network.name}/versions.json`, data);
  });

module.exports = {};