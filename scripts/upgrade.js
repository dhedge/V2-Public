const fs = require("fs");
const csv = require("csvtojson");
const { getTag } = require("./Helpers");
const Safe = require("@gnosis.pm/safe-core-sdk");
const { EthersAdapter } = require('@gnosis.pm/safe-core-sdk');
const { SafeService } = require("@gnosis.pm/safe-ethers-adapters");
const proxyAdminAddress = "0x0C0a10C9785a73018077dBC74B2A006695849252";
const safeAddress = "0xc715Aa67866A2FEF297B12Cb26E953481AeD2df4";
// https://github.com/gnosis/safe-deployments/blob/main/src/assets/v1.3.0/multi_send.json#L13
const multiSendAddress = "0xA238CBeb142c10Ef7Ad8442C6D1f9E89e07e7761";
const service = new SafeService("https://safe-transaction.polygon.gnosis.io");
const prodFileName = "./dHEDGE Assets list - Polygon.csv";
const stagingFileName = "./dHEDGE Assets list - Polygon Staging.csv";
let nonce, safeSdk;

const proposeTx = async(to, data) => {
  const transaction = {
    to: to,
    value: "0",
    data: data,
    nonce: nonce,
  };

  console.log("Proposing transaction: ", transaction);

  nonce += 1;

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
};

task("upgrade", "Upgrade proxy contracts")
  .addOptionalParam("poolFactory", "upgrade poolFactory", false, types.boolean)
  .addOptionalParam("assetHandler", "upgrade assetHandler", false, types.boolean)
  .addOptionalParam("poolLogic", "upgrade poolLogic", false, types.boolean)
  .addOptionalParam("poolManagerLogic", "upgrade poolManagerLogic", false, types.boolean)
  .addOptionalParam("production", "production environment", false, types.boolean)
  .setAction(async taskArgs => {
    // Initialize the Safe SDK
    const provider = ethers.provider;
    const owner1 = provider.getSigner(0);
    const ethAdapter = new EthersAdapter({ ethers: ethers, signer: owner1 });
    const chainId = await ethAdapter.getChainId();
    const hre = require("hardhat");

    const contractNetworks = {
      [chainId]: {
        multiSendAddress: multiSendAddress,
      }
    }

    const safeSdk = await Safe.default.create({
      ethAdapter,
      safeAddress: safeAddress,
      contractNetworks
    });
    nonce = await safeSdk.getNonce();
    const owner1Address = await owner1.getAddress();

    const network = await ethers.provider.getNetwork();
    console.log("network:", network);

    // Init tag
    const networks = hre.config.networks;
    const versionFile = taskArgs.production ? "versions" : "staging-versions"
    const versions = require(`../publish/${network.name}/${versionFile}.json`);
    let newTag = await getTag();
    let oldTag = Object.keys(versions)[Object.keys(versions).length - 1];
    console.log(`oldTag: ${oldTag}`);
    console.log(`newTag: ${newTag}`);
    if (newTag == oldTag) throw("Error: No new version to upgrade");

    // Init contracts data
    const ProxyAdmin = await hre.artifacts.readArtifact("ProxyAdmin");
    const proxyAdmin = new ethers.utils.Interface(ProxyAdmin.abi);

    let contracts = versions[oldTag].contracts;
    versions[newTag] = new Object;
    versions[newTag].contracts = { ...contracts };
    versions[newTag].network = network;
    versions[newTag].date = new Date().toUTCString();
    let setLogic = false;

    // look up to check if csvAsset is in the current versions
    let assetHandlerAssets = [];
    const fileName = taskArgs.production ? prodFileName : stagingFileName ;
    const csvAssets = await csv().fromFile(fileName);
    const SushiLPAggregator = await ethers.getContractFactory("SushiLPAggregator");
    for(const csvAsset of csvAssets){
      let foundInVersions = false;
      for(const asset of contracts.Assets){
        if(csvAsset["Asset Name"] === asset.name){
          console.log(`csvAsset: ${csvAsset["Asset Name"]} is already in the current contracts.Assets`);
          foundInVersions = true;
          break;
        }
      }
      if(!foundInVersions){
        const assetType = csvAsset.AssetType;
        switch (assetType) {
          case "2":
            // Deploy Sushi LP Aggregator
            console.log("Deploying ", csvAsset["Asset Name"]);
            const sushiLPAggregator = await SushiLPAggregator.deploy(csvAsset.Address, contracts.PoolFactoryProxy);
            await sushiLPAggregator.deployed();
            console.log(`${csvAsset["Asset Name"]} SushiLPAggregator deployed at `, sushiLPAggregator.address);
            assetHandlerAssets.push({
              name: csvAsset["Asset Name"],
              asset: csvAsset.Address,
              assetType: assetType,
              aggregator: sushiLPAggregator.address,
            });
            break;
          case "3":
            // Deploy USDPriceAggregator
            const USDPriceAggregator = await ethers.getContractFactory("USDPriceAggregator");
            usdPriceAggregator = await USDPriceAggregator.deploy();
            console.log("USDPriceAggregator deployed at ", usdPriceAggregator.address);
            assetHandlerAssets.push({
              name: csvAsset["Asset Name"],
              asset: csvAsset.Address,
              assetType: assetType,
              aggregator: usdPriceAggregator.address,
            });
            break;
          default:
            console.log(`Adding new asset: ${csvAsset["Asset Name"]}`);
            assetHandlerAssets.push({
              name: csvAsset["Asset Name"],
              asset: csvAsset.Address,
              assetType: assetType,
              aggregator: csvAsset["Chainlink Price Feed"],
            });
        }
      }
    }

    // const AssetHandlerLogic = await hre.artifacts.readArtifact("AssetHandler");
    // const assetHandlerLogic = new ethers.utils.Interface(AssetHandlerLogic.abi);
    // const addAssetsABI = assetHandlerLogic.encodeFunctionData("addAssets", [assetHandlerAssets]);

    if(assetHandlerAssets.length > 0){
      await proposeTx(contracts.AssetHandlerProxy, addAssetsABI);
    }
    if(taskArgs.poolFactory){
      let poolFactoryProxy = contracts.PoolFactoryProxy;
      const newPoolFactoryLogic = await upgrades.prepareUpgrade(poolFactoryProxy, PoolFactory);
      console.log("New PoolFactory logic deployed to: ", newPoolFactoryLogic);

      try{
        await hre.run("verify:verify", {
          address: newPoolFactoryLogic,
          contract: "contracts/PoolFactory.sol:PoolFactory",
        });
      }catch(err){
        console.log("Error: ", err);
      }

      const upgradeABI = proxyAdmin.encodeFunctionData("upgrade", [poolFactoryProxy, newPoolFactoryLogic]);
      await proposeTx(proxyAdminAddress, upgradeABI);
    }
    if(taskArgs.assetHandler){
      let oldAssetHandler = contracts.AssetHandlerProxy;
      const AssetHandler = await ethers.getContractFactory("AssetHandler");
      const assetHandler = await upgrades.prepareUpgrade(oldAssetHandler, AssetHandler);
      console.log("assetHandler logic deployed to: ", assetHandler);

      try{
        await hre.run("verify:verify", {
          address: assetHandler,
          contract: "contracts/assets/AssetHandler.sol:AssetHandler",
        });
      }catch(err){
        console.log("Error: ", err);
      }

      const upgradeABI = proxyAdmin.encodeFunctionData("upgrade", [oldAssetHandler, assetHandler]);
      await proposeTx(proxyAdminAddress, upgradeABI);
    }
    if(taskArgs.poolLogic){
      let oldPooLogicProxy = contracts.PoolLogicProxy;
      const PoolLogic = await ethers.getContractFactory("PoolLogic");
      const poolLogic = await upgrades.prepareUpgrade(oldPooLogicProxy, PoolLogic);
      console.log("poolLogic deployed to: ", poolLogic);
      versions[newTag].contracts.PoolLogic = poolLogic;
      setLogic = true;

      await hre.run("verify:verify", {
        address: poolLogic,
        contract: "contracts/PoolLogic.sol:PoolLogic",
      });
    }
    if(taskArgs.poolManagerLogic){
      let oldPooManagerLogicProxy = contracts.PoolManagerLogicProxy;
      const PoolManagerLogic = await ethers.getContractFactory("PoolManagerLogic");
      const poolManagerLogic = await upgrades.prepareUpgrade(oldPooManagerLogicProxy, PoolManagerLogic);
      console.log("poolManagerLogic deployed to: ", poolManagerLogic);
      versions[newTag].contracts.PoolManagerLogic = poolManagerLogic;
      setLogic = true;

      await hre.run("verify:verify", {
        address: poolManagerLogic,
        contract: "contracts/PoolManagerLogic.sol:PoolManagerLogic",
      });
    }
    if(setLogic){
      const PoolFactory = await hre.artifacts.readArtifact("PoolFactory");
      const poolFactory = new ethers.utils.Interface(PoolFactory.abi);
      const setLogicABI = poolFactory.encodeFunctionData("setLogic", [versions[newTag].contracts.PoolLogic, versions[newTag].contracts.PoolManagerLogic]);
      await proposeTx(contracts.PoolFactoryProxy, setLogicABI);
    }

    // convert JSON object to string
    const data = JSON.stringify(versions, null, 2);
    console.log(data);

    fs.writeFileSync(`./publish/${network.name}/${versionFile}.json`, data);
  });

module.exports = {};