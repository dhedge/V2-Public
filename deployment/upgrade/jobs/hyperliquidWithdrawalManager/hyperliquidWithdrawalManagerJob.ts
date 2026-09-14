import { getImplementationAddress } from "@openzeppelin/upgrades-core";
import { HardhatRuntimeEnvironment } from "hardhat/types";

import { proposeTx, tryVerify } from "../../../deploymentHelpers";
import { IAddresses, IFileNames, IJob, IUpgradeConfig, IVersions } from "../../../types";

export const hyperliquidWithdrawalManagerJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  _filenames: IFileNames,
  addresses: IAddresses,
) => {
  const hyperliquidConfig = addresses.hyperliquid;
  if (!hyperliquidConfig) {
    return console.warn("Hyperliquid configuration not found: skipping.");
  }

  const { admin } = hyperliquidConfig;
  if (!admin) {
    return console.warn("Hyperliquid admin not configured: skipping.");
  }

  if (versions[config.newTag].contracts.HyperliquidWithdrawalManagerProxy) {
    await upgradeHyperliquidWithdrawalManager(hre, config, versions, addresses);
  } else {
    await deployHyperliquidWithdrawalManager(hre, config, versions, addresses, admin);
  }
};

const upgradeHyperliquidWithdrawalManager = async (
  hre: HardhatRuntimeEnvironment,
  config: IUpgradeConfig,
  versions: IVersions,
  addresses: IAddresses,
) => {
  console.log("Upgrading HyperliquidWithdrawalManager");

  const ethers = hre.ethers;
  const upgrades = hre.upgrades;
  const ProxyAdmin = await hre.artifacts.readArtifact("ProxyAdmin");
  const proxyAdmin = new ethers.utils.Interface(ProxyAdmin.abi);

  const proxy = versions[config.oldTag].contracts.HyperliquidWithdrawalManagerProxy;

  const HyperliquidWithdrawalManager = await ethers.getContractFactory("HyperliquidWithdrawalManager");

  if (config.execute) {
    const newImplementation = await upgrades.prepareUpgrade(proxy as string, HyperliquidWithdrawalManager);
    console.log("New logic deployed to: ", newImplementation);

    await tryVerify(
      hre,
      newImplementation,
      "contracts/utils/hyperliquid/HyperliquidWithdrawalManager.sol:HyperliquidWithdrawalManager",
      [],
    );

    const upgradeABI = proxyAdmin.encodeFunctionData("upgrade", [proxy, newImplementation]);
    await proposeTx(addresses.proxyAdminAddress, upgradeABI, "Upgrade HyperliquidWithdrawalManager", config, addresses);

    versions[config.newTag].contracts.HyperliquidWithdrawalManager = newImplementation;

    console.log("HyperliquidWithdrawalManager upgraded. New Implementation address: ", newImplementation);
  }
};

const deployHyperliquidWithdrawalManager = async (
  hre: HardhatRuntimeEnvironment,
  config: IUpgradeConfig,
  versions: IVersions,
  addresses: IAddresses,
  admin: string,
) => {
  console.log("Deploying HyperliquidWithdrawalManager");

  const ethers = hre.ethers;
  const upgrades = hre.upgrades;
  const provider = ethers.provider;

  const poolFactoryProxy = versions[config.newTag].contracts.PoolFactoryProxy;
  const coreWriterGuardProxy = versions[config.newTag].contracts.HyperliquidCoreWriterContractGuardProxy;

  if (!poolFactoryProxy) return console.warn("PoolFactoryProxy missing... skipping.");

  if (!coreWriterGuardProxy) return console.warn("HyperliquidCoreWriterContractGuardProxy missing... skipping.");

  const HyperliquidWithdrawalManager = await ethers.getContractFactory("HyperliquidWithdrawalManager");
  const initParams: [string, string, string] = [admin, poolFactoryProxy, coreWriterGuardProxy];

  if (config.execute) {
    const withdrawalManager = await upgrades.deployProxy(HyperliquidWithdrawalManager, initParams);
    await withdrawalManager.deployed();
    const withdrawalManagerProxy = withdrawalManager.address;

    const withdrawalManagerImplementationAddress = await getImplementationAddress(provider, withdrawalManagerProxy);

    await tryVerify(
      hre,
      withdrawalManagerImplementationAddress,
      "contracts/utils/hyperliquid/HyperliquidWithdrawalManager.sol:HyperliquidWithdrawalManager",
      [],
    );

    versions[config.newTag].contracts.HyperliquidWithdrawalManagerProxy = withdrawalManagerProxy;
    versions[config.newTag].contracts.HyperliquidWithdrawalManager = withdrawalManagerImplementationAddress;

    console.log("HyperliquidWithdrawalManagerProxy deployed to: ", withdrawalManagerProxy);
    console.log("HyperliquidWithdrawalManager implementation: ", withdrawalManagerImplementationAddress);

    // The guard's txGuard no longer reads `withdrawalManager`, so calling setWithdrawalManager would have no
    // effect: the WM is deployed without being wired in, and its pool.execTransaction calls stay rejected
    // until the guard is extended again.
  }
};
