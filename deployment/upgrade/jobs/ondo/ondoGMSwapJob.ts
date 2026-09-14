import { getImplementationAddress } from "@openzeppelin/upgrades-core";
import { HardhatRuntimeEnvironment } from "hardhat/types";

import { proposeTx, tryVerify } from "../../../deploymentHelpers";
import { IAddresses, IFileNames, IJob, IUpgradeConfig, IVersions } from "../../../types";

export const ondoGMSwapJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  _filenames: IFileNames,
  addresses: IAddresses,
) => {
  if (!addresses.ondo?.gmTokenManager) return console.warn("ondo.gmTokenManager not configured... skipping.");
  if (!addresses.assets?.usdc) return console.warn("assets.usdc not configured... skipping.");

  const { gmTokenManager } = addresses.ondo;
  const { usdc } = addresses.assets;

  const ondoGMSwapProxy = versions[config.newTag].contracts.OndoGMSwapProxy;

  if (config.execute) {
    if (ondoGMSwapProxy) {
      await upgradeOndoGMSwap(hre, config, versions, addresses, ondoGMSwapProxy);
    } else {
      await deployOndoGMSwap(hre, config, versions, addresses, gmTokenManager, usdc);
    }
  }
};

const deployOndoGMSwap = async (
  hre: HardhatRuntimeEnvironment,
  config: IUpgradeConfig,
  versions: IVersions,
  addresses: IAddresses,
  gmTokenManager: string,
  usdc: string,
) => {
  console.log("Deploying OndoGMSwap");

  const ethers = hre.ethers;
  const upgrades = hre.upgrades;
  const provider = ethers.provider;

  if (!versions[config.oldTag].contracts.PoolFactoryProxy) return console.warn("PoolFactoryProxy missing... skipping.");

  const OndoGMSwap = await ethers.getContractFactory("OndoGMSwap");
  const initParams = [
    addresses.protocolDaoAddress, // owner
    versions[config.oldTag].contracts.PoolFactoryProxy,
    gmTokenManager,
    usdc,
  ];
  const ondoGMSwap = await upgrades.deployProxy(OndoGMSwap, initParams);
  await ondoGMSwap.deployed();
  const proxyAddress = ondoGMSwap.address;

  const implementationAddress = await getImplementationAddress(provider, proxyAddress);

  await tryVerify(hre, implementationAddress, "contracts/swappers/OndoGMSwap.sol:OndoGMSwap", []);

  versions[config.newTag].contracts.OndoGMSwapProxy = proxyAddress;
  versions[config.newTag].contracts.OndoGMSwap = implementationAddress;

  console.log("OndoGMSwapProxy deployed to: ", proxyAddress);
  console.log("OndoGMSwap implementation: ", implementationAddress);
};

const upgradeOndoGMSwap = async (
  hre: HardhatRuntimeEnvironment,
  config: IUpgradeConfig,
  versions: IVersions,
  addresses: IAddresses,
  proxy: string,
) => {
  console.log("Upgrading OndoGMSwap");

  const ethers = hre.ethers;
  const upgrades = hre.upgrades;
  const ProxyAdmin = await hre.artifacts.readArtifact("ProxyAdmin");
  const proxyAdmin = new ethers.utils.Interface(ProxyAdmin.abi);

  const OndoGMSwap = await ethers.getContractFactory("OndoGMSwap");
  const newLogic = await upgrades.prepareUpgrade(proxy, OndoGMSwap);
  console.log("New OndoGMSwap logic deployed to: ", newLogic);

  await tryVerify(hre, newLogic, "contracts/swappers/OndoGMSwap.sol:OndoGMSwap", []);

  const upgradeABI = proxyAdmin.encodeFunctionData("upgrade", [proxy, newLogic]);
  await proposeTx(addresses.proxyAdminAddress, upgradeABI, "Upgrade OndoGMSwap", config, addresses);

  versions[config.newTag].contracts.OndoGMSwap = newLogic;

  console.log("OndoGMSwap upgraded. New implementation: ", newLogic);
};
