import { getImplementationAddress } from "@openzeppelin/upgrades-core";
import { HardhatRuntimeEnvironment } from "hardhat/types";

import { proposeTx, tryVerify } from "../../deploymentHelpers";
import { IAddresses, IFileNames, IJob, IUpgradeConfig, IVersions } from "../../types";

export const referralManagerJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  _filenames: IFileNames,
  addresses: IAddresses,
) => {
  if (versions[config.newTag].contracts.ReferralManagerProxy) {
    await upgradeReferralManager(hre, config, versions, addresses);
  } else {
    await deployReferralManager(hre, config, versions, addresses);
  }
};

const upgradeReferralManager = async (
  hre: HardhatRuntimeEnvironment,
  config: IUpgradeConfig,
  versions: IVersions,
  addresses: IAddresses,
) => {
  console.log("Upgrading ReferralManager");

  const ethers = hre.ethers;
  const upgrades = hre.upgrades;
  const ProxyAdmin = await hre.artifacts.readArtifact("ProxyAdmin");
  const proxyAdmin = new ethers.utils.Interface(ProxyAdmin.abi);

  const proxy = versions[config.oldTag].contracts.ReferralManagerProxy;

  const ReferralManager = await ethers.getContractFactory("ReferralManager");

  if (config.execute) {
    const newImplementation = await upgrades.prepareUpgrade(proxy, ReferralManager);
    console.log("New logic deployed to: ", newImplementation);

    await tryVerify(hre, newImplementation, "contracts/referral/ReferralManager.sol:ReferralManager", []);

    const upgradeABI = proxyAdmin.encodeFunctionData("upgrade", [proxy, newImplementation]);
    await proposeTx(addresses.proxyAdminAddress, upgradeABI, "Upgrade ReferralManager", config, addresses);

    versions[config.newTag].contracts.ReferralManager = newImplementation;

    console.log("ReferralManager upgraded. New Implementation address: ", newImplementation);
  }
};

const deployReferralManager = async (
  hre: HardhatRuntimeEnvironment,
  config: IUpgradeConfig,
  versions: IVersions,
  addresses: IAddresses,
) => {
  console.log("Deploying ReferralManager");

  const ethers = hre.ethers;
  const upgrades = hre.upgrades;
  const provider = ethers.provider;

  const poolFactoryProxy = versions[config.newTag].contracts.PoolFactoryProxy;

  const ReferralManager = await ethers.getContractFactory("ReferralManager");
  const initParams = [poolFactoryProxy];

  if (config.execute) {
    const referralManager = await upgrades.deployProxy(ReferralManager, initParams);
    await referralManager.deployed();
    const referralManagerProxy = referralManager.address;

    // Retry with delay for RPC propagation
    let referralManagerImplementation: string | undefined;
    for (let i = 0; i < 5; i++) {
      try {
        referralManagerImplementation = await getImplementationAddress(provider, referralManagerProxy);
        break;
      } catch (e) {
        console.log(`Attempt ${i + 1}/5: Waiting for proxy to be indexed...`);
        await new Promise((resolve) => setTimeout(resolve, 5000));
      }
    }
    if (!referralManagerImplementation) {
      throw new Error(`Failed to get implementation address for proxy at ${referralManagerProxy} after retries`);
    }

    await tryVerify(hre, referralManagerImplementation, "contracts/referral/ReferralManager.sol:ReferralManager", []);

    versions[config.newTag].contracts.ReferralManagerProxy = referralManagerProxy;
    versions[config.newTag].contracts.ReferralManager = referralManagerImplementation;

    console.log("ReferralManagerProxy deployed to: ", referralManagerProxy);
    console.log("ReferralManager implementation: ", referralManagerImplementation);

    // Set the ReferralManager in PoolFactory
    const PoolFactory = await hre.artifacts.readArtifact("PoolFactory");
    const setReferralManagerTxData = new ethers.utils.Interface(PoolFactory.abi).encodeFunctionData(
      "setReferralManager",
      [referralManagerProxy],
    );
    await proposeTx(
      poolFactoryProxy,
      setReferralManagerTxData,
      "Set ReferralManager in PoolFactory",
      config,
      addresses,
    );
  }
};
