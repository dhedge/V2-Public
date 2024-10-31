import { getImplementationAddress } from "@openzeppelin/upgrades-core";
import { HardhatRuntimeEnvironment } from "hardhat/types";

import { proposeTx, tryVerify } from "../../../deploymentHelpers";
import { IAddresses, IFileNames, IJob, IUpgradeConfig, IVersions } from "../../../types";

export const easySwapperV2Job: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  _filenames: IFileNames,
  addresses: IAddresses,
) => {
  console.log("Will deploy EasySwapperV2");

  if (config.execute) {
    if (versions[config.newTag].contracts.EasySwapperV2Proxy) {
      await upgradeEasySwapperV2(hre, config, versions, addresses);
    } else {
      await deployEasySwapperV2(hre, config, versions, addresses);
    }
  }
};

const deployEasySwapperV2 = async (
  hre: HardhatRuntimeEnvironment,
  config: IUpgradeConfig,
  versions: IVersions,
  addresses: IAddresses,
) => {
  console.log("Deploying EasySwapperV2");

  const ethers = hre.ethers;
  const upgrades = hre.upgrades;
  const provider = ethers.provider;

  if (!versions[config.oldTag].contracts.PoolFactoryProxy) return console.warn("PoolFactoryProxy missing... skipping.");

  if (!versions[config.oldTag].contracts.WithdrawalVault) return console.warn("WithdrawalVault missing... skipping.");

  if (!addresses.flatMoney?.swapper) return console.warn("Swapper contract address missing... skipping.");

  const EasySwapperV2 = await ethers.getContractFactory("EasySwapperV2");
  const initParams = [
    versions[config.oldTag].contracts.WithdrawalVault,
    addresses.assets.weth,
    addresses.assets.nativeAssetWrapper,
    addresses.flatMoney.swapper,
    60 * 60, // 60 minutes
  ];
  const easySwapperV2 = await upgrades.deployProxy(EasySwapperV2, initParams);
  await easySwapperV2.deployed();
  const easySwapperV2ProxyAddress = easySwapperV2.address;

  const easySwapperV2ImplementationAddress = await getImplementationAddress(provider, easySwapperV2ProxyAddress);

  await tryVerify(
    hre,
    easySwapperV2ImplementationAddress,
    "contracts/swappers/easySwapperV2/EasySwapperV2.sol:EasySwapperV2",
    [],
  );

  versions[config.newTag].contracts.EasySwapperV2Proxy = easySwapperV2ProxyAddress;
  versions[config.newTag].contracts.EasySwapperV2 = easySwapperV2ImplementationAddress;

  console.log("EasySwapperV2Proxy deployed to: ", easySwapperV2ProxyAddress);
  console.log("EasySwapperV2 implementation: ", easySwapperV2ImplementationAddress);

  const poolFactoryProxy = versions[config.newTag].contracts.PoolFactoryProxy;
  const PoolFactory = await hre.artifacts.readArtifact("PoolFactory");
  const addCustomCooldownWhitelistData = new ethers.utils.Interface(PoolFactory.abi).encodeFunctionData(
    "addCustomCooldownWhitelist",
    [easySwapperV2ProxyAddress],
  );
  await proposeTx(
    poolFactoryProxy,
    addCustomCooldownWhitelistData,
    "Add new EasySwapperV2 to whitelist",
    config,
    addresses,
  );

  await EasySwapperV2.attach(easySwapperV2ProxyAddress).setdHedgePoolFactory(
    versions[config.oldTag].contracts.PoolFactoryProxy,
  );

  await EasySwapperV2.attach(easySwapperV2ProxyAddress).transferOwnership(addresses.protocolDaoAddress);
};

const upgradeEasySwapperV2 = async (
  hre: HardhatRuntimeEnvironment,
  config: IUpgradeConfig,
  versions: IVersions,
  addresses: IAddresses,
) => {
  console.log("Upgrading EasySwapperV2");

  const ethers = hre.ethers;
  const upgrades = hre.upgrades;
  const ProxyAdmin = await hre.artifacts.readArtifact("ProxyAdmin");
  const proxyAdmin = new ethers.utils.Interface(ProxyAdmin.abi);

  const proxy = versions[config.oldTag].contracts.EasySwapperV2Proxy;

  const EasySwapperV2 = await ethers.getContractFactory("EasySwapperV2");
  const newLogic = await upgrades.prepareUpgrade(proxy, EasySwapperV2);
  console.log("New logic deployed to: ", newLogic);
  const implementation = await ethers.getContractAt("EasySwapperV2", newLogic);

  await tryVerify(hre, newLogic, "contracts/swappers/easySwapperV2/EasySwapperV2.sol:EasySwapperV2", []);

  const upgradeABI = proxyAdmin.encodeFunctionData("upgrade", [proxy, newLogic]);
  await proposeTx(addresses.proxyAdminAddress, upgradeABI, "Upgrade EasySwapperV2", config, addresses);

  versions[config.newTag].contracts.EasySwapperV2 = implementation.address;

  console.log("EasySwapperV2 upgraded. New Implementation address: ", implementation.address);
};
