import { ethers, upgrades } from "hardhat";
import fs from "fs";
import csv from "csvtojson";
import { version } from "chai";

const { getTag } = require("../Helpers");

const addresses = {
  LEET: "0x0000000000000000000000000000000000001337",
  protocolDao: "0xc715Aa67866A2FEF297B12Cb26E953481AeD2df4",
  uberPool: "0xc715Aa67866A2FEF297B12Cb26E953481AeD2df4",

  sUSD: "0x8c6f28f2f1a3c87f0f938b96d27520d9751ec8d9",
  synthetixProxyAddress: "0x8700dAec35aF8Ff88c16BdF0418774CB3D7599B4",
  synthetixAddressResolverAddress: "0x95A6a3f44a70172E7d50a9e28c85Dfd712756B8C",

  implementationStorage: "0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc",
};

const fileNames = {
  ovmVersionFile: "./publish/ovm/prod/versions.json",
  chainlinkAssetsFile: "./config/prod-ovm/dHEDGE Chainlink Assets.csv",
  usdPriceAggregatorAssetsFile: "./config/prod-ovm/dHEDGE USDPriceAggregator Assets.csv",
};

type Address = string;

interface IContracts {
  Governance?: Address;
  PoolFactoryProxy?: Address;
  PoolLogic?: { proxy: Address; impl: Address };
  PoolManagerLogic?: { proxy: Address; impl: Address };
  AssetHandlerProxy?: Address;
  PoolPerformanceProxy?: Address;
  SynthetixGuard?: Address;
  ERC20Guard?: Address;
  USDPriceAggregator?: Address;
  Assets?: { name: string; asset: Address; assetType: number; aggregator: Address }[];
}

type IVersions = {
  [version: string]: {
    network: string;
    lastUpdated: string;
    contracts: IContracts;
  };
};

interface IChainlinkAsset {
  AssetName: string;
  Address: string;
  AssetType: string;
  ChainlinkPriceFeed: string;
}

interface IUSDAsset {
  AssetName: string;
  Address: string;
  AssetType: string;
}

const versions: IVersions = JSON.parse(fs.readFileSync(fileNames.ovmVersionFile, "utf-8"));

const writeVersions = () => {
  const versionsStringified = JSON.stringify(versions, null, 2);
  console.log(versionsStringified);
  fs.writeFileSync(fileNames.ovmVersionFile, versionsStringified);
};

async function main() {
  const tag = await getTag();
  versions[tag] = versions[tag] || {};

  const addToVersions = <K extends keyof IContracts>(key: K, value: IContracts[K]) => {
    versions[tag].lastUpdated = new Date().toUTCString();
    versions[tag].contracts = versions[tag].contracts || {};
    versions[tag].contracts[key] = value;
  };

  const checkDeployed = <K extends keyof IContracts>(key: K, opts: { throw: boolean } = { throw: false }) => {
    if (versions[tag].contracts && versions[tag].contracts[key]) {
      if (!opts.throw) {
        console.log(key + " Already Deployed to:", versions[tag].contracts[key]);
      }
      return true;
    }
    if (opts.throw) {
      throw new Error(key + " Not Deployed.");
    }
    return false;
  };

  const deployers: { [k in keyof IContracts]: () => Promise<void> } = {
    Governance: async () => {
      if (checkDeployed("Governance")) return;
      const Governance = await ethers.getContractFactory("Governance");
      const governance = await Governance.deploy();

      const ERC20Guard = await ethers.getContractFactory("ERC20Guard");
      const erc20Guard = await ERC20Guard.deploy();
      await erc20Guard.deployed();
      addToVersions("ERC20Guard", erc20Guard.address);
      console.log("ERC20Guard deployed at ", erc20Guard.address);

      await governance.setAssetGuard(0, erc20Guard.address);

      const SynthetixGuardFactory = await ethers.getContractFactory("SynthetixGuard");
      const synthetixGuard = await SynthetixGuardFactory.deploy(addresses.synthetixAddressResolverAddress);
      await synthetixGuard.deployed();
      addToVersions("SynthetixGuard", synthetixGuard.address);
      console.log("UniswapV2RouterGuard deployed at ", synthetixGuard.address);

      await governance.setContractGuard(addresses.synthetixProxyAddress, synthetixGuard.address);
      await governance.transferOwnership(addresses.protocolDao);
      addToVersions("Governance", governance.address);
      console.log("Governance deployed to:", governance.address);
    },
    USDPriceAggregator: async () => {
      if (checkDeployed("USDPriceAggregator")) return;
      const USDPriceAggregator = await ethers.getContractFactory("USDPriceAggregator");
      const usdPriceAggregator = await USDPriceAggregator.deploy();
      console.log("USDPriceAggregator deployed at ", usdPriceAggregator.address);
      addToVersions("USDPriceAggregator", usdPriceAggregator.address);
    },
    AssetHandlerProxy: async () => {
      if (checkDeployed("AssetHandlerProxy")) return;

      checkDeployed("USDPriceAggregator", { throw: true });

      const AssetHandlerLogic = await ethers.getContractFactory("AssetHandler");
      const assetHandler = await upgrades.deployProxy(AssetHandlerLogic, [[]]);
      await assetHandler.deployed();

      const chainLinkAssets: IChainlinkAsset[] = await csv().fromFile(fileNames.chainlinkAssetsFile);
      const chainlinkAssetHandlers = chainLinkAssets.map((asset) => {
        return {
          name: asset.AssetName,
          asset: asset.Address,
          assetType: asset.AssetType,
          aggregator: asset.ChainlinkPriceFeed,
        };
      });

      const usdAssets: IUSDAsset[] = await csv().fromFile(fileNames.usdPriceAggregatorAssetsFile);
      const usdAssetHandlers = usdAssets.map((asset) => {
        return {
          name: asset.AssetName,
          asset: asset.Address,
          assetType: asset.AssetType,
          aggregator: versions[tag].contracts.USDPriceAggregator,
        };
      });

      const allAssets = [...chainlinkAssetHandlers, ...usdAssetHandlers];
      allAssets.forEach((asset) => console.log("Adding Asset: ", asset.name));
      await assetHandler.addAssets([...chainlinkAssetHandlers, ...usdAssetHandlers]);
      await assetHandler.transferOwnership(addresses.protocolDao);
      addToVersions("AssetHandlerProxy", assetHandler.address);
      console.log("AssetHandler deployed at ", assetHandler.address);
    },
    PoolPerformanceProxy: async () => {
      if (checkDeployed("PoolPerformanceProxy")) return;
      const PoolPerformance = await ethers.getContractFactory("PoolPerformance");
      const poolPerformance = await upgrades.deployProxy(PoolPerformance);
      await poolPerformance.deployed();
      await poolPerformance.transferOwnership(addresses.protocolDao);
      addToVersions("PoolPerformanceProxy", poolPerformance.address);
      console.log("PoolPerformance deployed at ", poolPerformance.address);
    },
    PoolFactoryProxy: async () => {
      if (checkDeployed("PoolFactoryProxy")) return;

      checkDeployed("AssetHandlerProxy", { throw: true });
      checkDeployed("PoolPerformanceProxy", { throw: true });

      const PoolLogic = await ethers.getContractFactory("PoolLogic");
      const poolLogic = await PoolLogic.deploy();

      const PoolManagerLogic = await ethers.getContractFactory("PoolManagerLogic");
      const poolManagerLogic = await PoolManagerLogic.deploy();

      const contracts = versions[tag].contracts;

      const PoolFactory = await ethers.getContractFactory("PoolFactory");

      const poolFactory = await upgrades.deployProxy(PoolFactory, [
        poolLogic.address,
        poolManagerLogic.address,
        contracts.AssetHandlerProxy,
        addresses.protocolDao,
        contracts.Governance,
      ]);

      await poolFactory.deployed();
      await poolFactory.setDAOAddress(addresses.uberPool);
      await poolFactory.setPoolPerformanceAddress(contracts.PoolPerformanceProxy);
      await poolFactory.transferOwnership(addresses.protocolDao);
      addToVersions("PoolFactoryProxy", poolFactory.address);
      console.log("poolFactory deployed at ", poolFactory.address);
    },
    PoolLogic: async () => {
      if (checkDeployed("PoolLogic")) return;

      checkDeployed("PoolFactoryProxy", { throw: true });

      const PoolLogic = await ethers.getContractFactory("PoolLogic");
      const poolLogic = await PoolLogic.deploy();
      console.log("PoolLogic deployed at ", poolLogic.address);

      const poolLogicProxy = await upgrades.deployProxy(PoolLogic, [
        versions[tag].contracts.PoolFactoryProxy,
        false,
        "NA",
        "NA",
      ]);
      console.log("PoolLogicProxy deployed at ", poolLogicProxy.address);
      const poolLogicAddressX = await ethers.provider.getStorageAt(
        poolLogicProxy.address,
        addresses.implementationStorage,
      );
      const poolLogicAddress = ethers.utils.hexValue(poolLogicAddressX);
      addToVersions("PoolLogic", { proxy: poolLogicProxy.address, impl: poolLogicAddress });
      console.log("poolLogicProxy deployed at ", poolLogicProxy.address);
    },
    PoolManagerLogic: async () => {
      if (checkDeployed("PoolManagerLogic")) return;

      checkDeployed("PoolLogic", { throw: true });
      checkDeployed("PoolFactoryProxy", { throw: true });

      const PoolManagerLogic = await ethers.getContractFactory("PoolManagerLogic");
      const poolManagerLogicProxy = await upgrades.deployProxy(PoolManagerLogic, [
        versions[tag].contracts.PoolFactoryProxy,
        addresses.LEET,
        "ManagerName",
        versions[tag].contracts.PoolLogic?.proxy,
        "1000",
        [[addresses.sUSD, true]],
      ]);
      console.log("Deployed PoolManagerLogic");
      const poolManagerLogicAddressX = await ethers.provider.getStorageAt(
        poolManagerLogicProxy.address,
        addresses.implementationStorage,
      );
      const poolManagerLogicAddress = ethers.utils.hexValue(poolManagerLogicAddressX);
      addToVersions("PoolManagerLogic", { proxy: poolManagerLogicProxy.address, impl: poolManagerLogicAddress });
      console.log("poolManagerLogicProxy deployed at ", poolManagerLogicProxy.address);
    },
  };

  console.log("Starting deployment");
  for (const deployer of Object.values(deployers)) {
    await deployer();
  }
  console.log("Deployment Finished. Well done.");
}

main().finally(() => {
  console.log("Writing Versions");
  writeVersions();
});
