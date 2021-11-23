import { ethers, upgrades } from "hardhat";
import { getImplementationAddress } from "@openzeppelin/upgrades-core";

import fs from "fs";
import csv from "csvtojson";
import { assets, synthetix } from "../../test/integration/ovm/ovm-data";
import { PoolManagerLogic__factory } from "../../types/factories/PoolManagerLogic__factory";
import { Proxy } from "../../types/Proxy.d";

const { getTag } = require("../Helpers");

0xef31d75a2f85cfdd9032158a2ceb773c84d79192;
0x6fc0411fcd7f1ab7ff99dd7eb697e6c660bebddb;
0x253956aedc059947e700071bc6d74bd8e34fe2ab;

const addresses = {
  LEET: "0x0000000000000000000000000000000000001337",
  // https://ogg.scopelift.co/wallet/0xeB03C960EC60b2159B3EcCfb341cE8d7e1268B08
  protocolDao: "0xeB03C960EC60b2159B3EcCfb341cE8d7e1268B08",
  // https://ogg.scopelift.co/wallet/0x2b0763A33b4D3DC8D6c1A4916D0f9467d6E11FFc
  uberPool: "0x2b0763A33b4D3DC8D6c1A4916D0f9467d6E11FFc",

  sUSD: assets.susd,
  synthetixProxyAddress: assets.snxProxy,
  synthetixAddressResolverAddress: synthetix.addressResolver,
  implementationStorage: "0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc",
};

const fileNames = {
  ovmVersionFile: "./publish/ovm/prod/versions.json",
  chainlinkAssetsFile: "./config/prod-ovm/assets/Chainlink Assets.csv",
  usdPriceAggregatorAssetsFile: "./config/prod-ovm/assets/USDPriceAggregator Assets.csv",
};

type Address = string;

interface IContracts {
  Governance?: Address;
  PoolLogicTemp?: string;
  PoolManagerLogicTemp?: string;
  PoolFactory?: { proxy: Address; implementation: Address };
  PoolLogic?: { proxy: Address; implementation: Address };
  PoolManagerLogic?: { proxy: Address; implementation: Address };
  AssetHandler?: { proxy: Address; implementation: Address };
  PoolPerformance?: { proxy: Address; implementation: Address };
  SynthetixGuard?: Address;
  ERC20Guard?: Address;
  USDPriceAggregator?: Address;
  Assets?: { name: string; asset: Address; assetType: number; aggregator: Address }[];
}

export type IVersions = {
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
  console.log("Writing Versions");
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
      await governance.deployed();

      const ERC20Guard = await ethers.getContractFactory("ERC20Guard");
      const erc20Guard = await ERC20Guard.deploy();
      await erc20Guard.deployed();

      addToVersions("ERC20Guard", erc20Guard.address);
      console.log("ERC20Guard deployed at ", erc20Guard.address);

      await governance.setAssetGuard(0, erc20Guard.address);
      await governance.setAssetGuard(1, erc20Guard.address);

      const SynthetixGuardFactory = await ethers.getContractFactory("SynthetixGuard");
      const synthetixGuard = await SynthetixGuardFactory.deploy(addresses.synthetixAddressResolverAddress);
      await synthetixGuard.deployed();
      addToVersions("SynthetixGuard", synthetixGuard.address);
      console.log("SynthetixGuard deployed at ", synthetixGuard.address);

      await governance.setContractGuard(addresses.synthetixProxyAddress, synthetixGuard.address);
      await governance.transferOwnership(addresses.protocolDao);
      addToVersions("Governance", governance.address);
      console.log("Governance deployed to:", governance.address);
    },
    USDPriceAggregator: async () => {
      if (checkDeployed("USDPriceAggregator")) return;
      const USDPriceAggregator = await ethers.getContractFactory("USDPriceAggregator");
      const usdPriceAggregator = await USDPriceAggregator.deploy();
      await usdPriceAggregator.deployed();
      console.log("USDPriceAggregator deployed at ", usdPriceAggregator.address);
      addToVersions("USDPriceAggregator", usdPriceAggregator.address);
    },
    AssetHandler: async () => {
      if (checkDeployed("AssetHandler")) return;

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
      const assetHandlerImplementation = await getImplementationAddress(ethers.provider, assetHandler.address);
      addToVersions("AssetHandler", { proxy: assetHandler.address, implementation: assetHandlerImplementation });
      console.log("AssetHandler deployed at ", assetHandler.address);
    },
    PoolPerformance: async () => {
      if (checkDeployed("PoolPerformance")) return;
      const PoolPerformance = await ethers.getContractFactory("PoolPerformance");
      const poolPerformance = await upgrades.deployProxy(PoolPerformance);
      await poolPerformance.deployed();
      await poolPerformance.transferOwnership(addresses.protocolDao);
      const poolPerformanceImplementation = await getImplementationAddress(ethers.provider, poolPerformance.address);
      addToVersions("PoolPerformance", {
        proxy: poolPerformance.address,
        implementation: poolPerformanceImplementation,
      });
      console.log("PoolPerformance deployed at ", poolPerformance.address);
    },
    PoolLogic: async () => {
      if (checkDeployed("PoolLogic")) return;
      ///
      /// Note: The proxy we deploy here is no used by the PoolFactory (or by anything else).
      /// The PoolFactory deploys its own Proxy Pattern for PoolLogic and PoolManagerLogic
      /// The proxy is only created and stored so that we can use the hardhat tools to
      /// check that the new implementation we are deploying is compatible with the existing storage
      ///
      const PoolLogic = await ethers.getContractFactory("PoolLogic");
      const poolLogicProxy = await upgrades.deployProxy(PoolLogic, [], { initializer: false });
      console.log("PoolLogicProxy deployed at ", poolLogicProxy.address);
      const poolLogicAddressX = await ethers.provider.getStorageAt(
        poolLogicProxy.address,
        addresses.implementationStorage,
      );
      const poolLogicAddress = ethers.utils.hexValue(poolLogicAddressX);
      addToVersions("PoolLogic", { proxy: poolLogicProxy.address, implementation: poolLogicAddress });
      console.log("poolLogicProxy deployed at ", poolLogicProxy.address);
    },
    PoolManagerLogic: async () => {
      if (checkDeployed("PoolManagerLogic")) return;

      ///
      /// Note: The proxy we deploy here is no used by the PoolFactory (or by anything else).
      /// The PoolFactory deploys its own Proxy Pattern for PoolLogic and PoolManagerLogic
      /// The proxy is only created and stored so that we can use the hardhat tools to
      /// check that the new implementation we are upgrading to is compatible with the existing storage.
      ///
      const PoolManagerLogic = await ethers.getContractFactory("PoolManagerLogic");
      const poolManagerLogicProxy = await upgrades.deployProxy(PoolManagerLogic, [], { initializer: false });
      console.log("Deployed PoolManagerLogic");
      const poolManagerLogicAddressX = await ethers.provider.getStorageAt(
        poolManagerLogicProxy.address,
        addresses.implementationStorage,
      );
      const poolManagerLogicAddress = ethers.utils.hexValue(poolManagerLogicAddressX);
      addToVersions("PoolManagerLogic", {
        proxy: poolManagerLogicProxy.address,
        implementation: poolManagerLogicAddress,
      });
      console.log("poolManagerLogicProxy deployed at ", poolManagerLogicProxy.address);
    },
    PoolFactory: async () => {
      if (checkDeployed("PoolFactory")) return;

      checkDeployed("AssetHandler", { throw: true });
      checkDeployed("PoolPerformance", { throw: true });
      checkDeployed("PoolLogic", { throw: true });
      checkDeployed("PoolManagerLogic", { throw: true });

      const contracts = versions[tag].contracts;

      const PoolFactory = await ethers.getContractFactory("PoolFactory");

      const poolFactory = await upgrades.deployProxy(PoolFactory, [
        contracts.PoolLogic?.implementation,
        contracts.PoolManagerLogic?.implementation,
        contracts.AssetHandler?.proxy,
        addresses.protocolDao,
        contracts.Governance,
      ]);

      await poolFactory.deployed();
      await poolFactory.setDAOAddress(addresses.uberPool);
      await poolFactory.setPoolPerformanceAddress(contracts.PoolPerformance?.proxy);
      await poolFactory.transferOwnership(addresses.protocolDao);
      const poolFactoryImplementation = await getImplementationAddress(ethers.provider, poolFactory.address);
      addToVersions("PoolFactory", { proxy: poolFactory.address, implementation: poolFactoryImplementation });
      console.log("poolFactory deployed at ", poolFactory.address);
    },
  };

  console.log("Starting deployment");
  for (const deployer of Object.values(deployers)) {
    await deployer();
  }
  console.log("Deployment Finished. Well done.");
}

main().finally(() => {
  writeVersions();
});
