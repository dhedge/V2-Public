import { ethers, upgrades } from "hardhat";
import { getImplementationAddress } from "@openzeppelin/upgrades-core";

import fs from "fs";
import csv from "csvtojson";

import { assert } from "chai";
import { ICSVAsset, IAddresses, IContracts, IVersions } from "./types";
import { IDeploymentData } from "./upgrade/getDeploymentData";

const { getTag } = require("../Helpers");

export async function deploy(deploymentData: IDeploymentData) {
  const { filenames, addresses } = deploymentData;
  const versions: IVersions = JSON.parse(fs.readFileSync(filenames.versionsFileName, "utf-8"));

  const writeVersions = () => {
    console.log("Writing Versions");
    const versionsStringified = JSON.stringify(versions, null, 2);
    console.log(versionsStringified);
    fs.writeFileSync(filenames.versionsFileName, versionsStringified);
  };

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

  const checkSet = <K extends keyof IAddresses>(addresses: IAddresses, key: K) => {
    if (!addresses[key]) {
      throw new Error(key + " is not set in addresses.");
    }
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

      const SynthetixGuardFactory = await ethers.getContractFactory("SynthetixGuard");
      checkSet(addresses, "synthetixAddressResolverAddress");
      const synthetixGuard = await SynthetixGuardFactory.deploy(addresses.synthetixAddressResolverAddress!);
      await synthetixGuard.deployed();
      addToVersions("SynthetixGuard", synthetixGuard.address);
      console.log("SynthetixGuard deployed at ", synthetixGuard.address);
      checkSet(addresses, "synthetixProxyAddress");
      await governance.setContractGuard(addresses.synthetixProxyAddress!, synthetixGuard.address);
      await governance.transferOwnership(addresses.protocolDaoAddress);
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

      const csvAssets: ICSVAsset[] = await csv().fromFile(filenames.assetsFileName);
      const assetHandlers: ICSVAsset[] = csvAssets.map((asset) => {
        if (asset.oracleAddress) {
          return asset;
        }
        if (asset.oracleName == "USDPriceAggregator") {
          return {
            ...asset,
            oracleAddress: versions[tag].contracts.USDPriceAggregator || "",
            oracleName: "USDPriceAggregator",
          };
        }
        throw new Error("No code path for this asset");
      });

      const allAssets = [...assetHandlers];
      allAssets.forEach((asset) => console.log("Adding Asset: ", asset.assetName));

      await assetHandler.addAssets(allAssets);
      await assetHandler.transferOwnership(addresses.protocolDaoAddress);
      const assetHandlerImplementation = await getImplementationAddress(ethers.provider, assetHandler.address);
      addToVersions("Assets", allAssets);
      addToVersions("AssetHandlerProxy", assetHandler.address);
      addToVersions("AssetHandler", assetHandlerImplementation);
      console.log("AssetHandler deployed at ", assetHandler.address);
    },
    PoolPerformance: async () => {
      if (checkDeployed("PoolPerformance")) return;
      const PoolPerformance = await ethers.getContractFactory("PoolPerformance");
      const poolPerformance = await upgrades.deployProxy(PoolPerformance);
      await poolPerformance.deployed();
      await poolPerformance.transferOwnership(addresses.protocolDaoAddress);
      const poolPerformanceImplementation = await getImplementationAddress(ethers.provider, poolPerformance.address);
      addToVersions("PoolPerformanceProxy", poolPerformance.address);
      addToVersions("PoolPerformance", poolPerformanceImplementation);
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
      await poolLogicProxy.deployed();
      const poolLogicAddressX = await ethers.provider.getStorageAt(
        poolLogicProxy.address,
        addresses.implementationStorageAddress,
      );
      const poolLogicAddress = ethers.utils.hexValue(poolLogicAddressX);
      addToVersions("PoolLogicProxy", poolLogicProxy.address);
      addToVersions("PoolLogic", poolLogicAddress);
      console.log("PoolLogicProxy deployed at ", poolLogicProxy.address);
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
      await poolManagerLogicProxy.deployed();
      console.log("Deployed PoolManagerLogic");
      const poolManagerLogicAddressX = await ethers.provider.getStorageAt(
        poolManagerLogicProxy.address,
        addresses.implementationStorageAddress,
      );
      const poolManagerLogicAddress = ethers.utils.hexValue(poolManagerLogicAddressX);
      addToVersions("PoolManagerLogicProxy", poolManagerLogicProxy.address);
      addToVersions("PoolManagerLogic", poolManagerLogicAddress);
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
        contracts.PoolLogic,
        contracts.PoolManagerLogic,
        contracts.AssetHandlerProxy,
        addresses.protocolDaoAddress,
        contracts.Governance,
      ]);

      await poolFactory.deployed();
      await poolFactory.setDAOAddress(addresses.protocolTreasuryAddress);
      await poolFactory.setPoolPerformanceAddress(contracts.PoolPerformanceProxy);
      await poolFactory.transferOwnership(addresses.protocolDaoAddress);
      const poolFactoryImplementation = await getImplementationAddress(ethers.provider, poolFactory.address);
      const poolFactoryImpl = PoolFactory.attach(poolFactoryImplementation);
      // There is a security issue where if we don't initialize the impl someone else can take take ownership
      // Using this they can escalate to destroy the contract.
      try {
        await poolFactoryImpl.implInitializer();
      } catch (e) {
        assert(e.error.message.includes("already initialized"), "PoolFactory implementation should be initialised");
      }

      await addToVersions("PoolFactoryProxy", poolFactory.address);
      await addToVersions("PoolFactory", poolFactoryImplementation);
      console.log("poolFactory deployed at ", poolFactory.address);
    },
  };

  console.log("Starting deployment");
  try {
    for (const deployer of Object.values(deployers)) {
      await deployer();
    }
    console.log("Deployment Finished. Well done.");
  } catch (e) {
    console.error(e);
  } finally {
    writeVersions();
  }
}
