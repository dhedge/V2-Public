import { getImplementationAddress } from "@openzeppelin/upgrades-core";
import { HardhatRuntimeEnvironment } from "hardhat/types";

import { proposeTx, tryVerify } from "../../../deploymentHelpers";
import { IAddresses, IFileNames, IJob, IUpgradeConfig, IVersions } from "../../../types";
import { PoolLimitOrderManager as PoolLimitOrderManagerType } from "../../../../types";

export const poolLimitOrderManagerJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  _filenames: IFileNames,
  addresses: IAddresses,
) => {
  if (versions[config.newTag].contracts.PoolLimitOrderManagerProxy) {
    await upgradePoolLimitOrderManager(hre, config, versions, addresses);
  } else {
    await deployPoolLimitOrderManager(hre, config, versions, addresses);
  }
};

const upgradePoolLimitOrderManager = async (
  hre: HardhatRuntimeEnvironment,
  config: IUpgradeConfig,
  versions: IVersions,
  addresses: IAddresses,
) => {
  console.log("Upgrading PoolLimitOrderManager");

  const ethers = hre.ethers;
  const upgrades = hre.upgrades;
  const ProxyAdmin = await hre.artifacts.readArtifact("ProxyAdmin");
  const proxyAdmin = new ethers.utils.Interface(ProxyAdmin.abi);

  const proxy = versions[config.oldTag].contracts.PoolLimitOrderManagerProxy;

  const PoolLimitOrderManager = await ethers.getContractFactory("PoolLimitOrderManager");

  if (config.execute) {
    const newImplementation = await upgrades.prepareUpgrade(proxy, PoolLimitOrderManager);
    console.log("New logic deployed to: ", newImplementation);

    await tryVerify(
      hre,
      newImplementation,
      "contracts/limitOrders/PoolLimitOrderManager.sol:PoolLimitOrderManager",
      [],
    );

    const upgradeABI = proxyAdmin.encodeFunctionData("upgrade", [proxy, newImplementation]);
    await proposeTx(addresses.proxyAdminAddress, upgradeABI, "Upgrade PoolLimitOrderManager", config, addresses);

    versions[config.newTag].contracts.PoolLimitOrderManager = newImplementation;

    console.log("PoolLimitOrderManager upgraded. New Implementation address: ", newImplementation);
  }
};

const deployPoolLimitOrderManager = async (
  hre: HardhatRuntimeEnvironment,
  config: IUpgradeConfig,
  versions: IVersions,
  addresses: IAddresses,
) => {
  console.log("Deploying PoolLimitOrderManager");

  const ethers = hre.ethers;
  const upgrades = hre.upgrades;
  const provider = ethers.provider;

  const poolFactoryProxy = versions[config.newTag].contracts.PoolFactoryProxy;
  const easySwapperV2Proxy = versions[config.newTag].contracts.EasySwapperV2Proxy;

  if (!poolFactoryProxy) return console.warn("PoolFactoryProxy missing... skipping.");

  if (!easySwapperV2Proxy) return console.warn("EasySwapperV2Proxy missing... skipping.");

  const PoolLimitOrderManager = await ethers.getContractFactory("PoolLimitOrderManager");
  const initParams: Parameters<PoolLimitOrderManagerType["initialize"]> = [
    addresses.protocolDaoAddress,
    poolFactoryProxy,
    easySwapperV2Proxy,
    addresses.poolLimitOrderManager.defaultSlippageTolerance,
    addresses.poolLimitOrderManager.settlementToken,
  ];

  if (config.execute) {
    const poolLimitOrderManager = await upgrades.deployProxy(PoolLimitOrderManager, initParams);
    await poolLimitOrderManager.deployed();
    const poolLimitOrderManagerProxy = poolLimitOrderManager.address;

    const poolLimitOrderManagerImplementationAddress = await getImplementationAddress(
      provider,
      poolLimitOrderManagerProxy,
    );

    await tryVerify(
      hre,
      poolLimitOrderManagerImplementationAddress,
      "contracts/limitOrders/PoolLimitOrderManager.sol:PoolLimitOrderManager",
      [],
    );

    versions[config.newTag].contracts.PoolLimitOrderManagerProxy = poolLimitOrderManagerProxy;
    versions[config.newTag].contracts.PoolLimitOrderManager = poolLimitOrderManagerImplementationAddress;

    console.log("PoolLimitOrderManagerProxy deployed to: ", poolLimitOrderManagerProxy);
    console.log("PoolLimitOrderManager implementation: ", poolLimitOrderManagerImplementationAddress);

    const EasySwapperV2 = await hre.artifacts.readArtifact("EasySwapperV2");
    const setAuthorizedWithdrawersTxData = new ethers.utils.Interface(EasySwapperV2.abi).encodeFunctionData(
      "setAuthorizedWithdrawers",
      [[{ toWhitelist: poolLimitOrderManagerProxy, whitelisted: true }]],
    );
    await proposeTx(
      easySwapperV2Proxy,
      setAuthorizedWithdrawersTxData,
      "Add authorized withdrawer to EasySwapperV2",
      config,
      addresses,
    );
  }
};
