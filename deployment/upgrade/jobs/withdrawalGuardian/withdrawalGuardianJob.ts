import { getImplementationAddress } from "@openzeppelin/upgrades-core";
import { HardhatRuntimeEnvironment } from "hardhat/types";

import { proposeTx, tryVerify } from "../../../deploymentHelpers";
import { IAddresses, IFileNames, IJob, IUpgradeConfig, IVersions } from "../../../types";

const WITHDRAWAL_DELAY = 3 * 24 * 60 * 60; // 3 days in seconds

export const withdrawalGuardianJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  _filenames: IFileNames,
  addresses: IAddresses,
) => {
  if (versions[config.newTag].contracts.WithdrawalGuardianProxy) {
    await upgradeWithdrawalGuardian(hre, config, versions, addresses);
  } else {
    await deployWithdrawalGuardian(hre, config, versions, addresses);
  }
};

const upgradeWithdrawalGuardian = async (
  hre: HardhatRuntimeEnvironment,
  config: IUpgradeConfig,
  versions: IVersions,
  addresses: IAddresses,
) => {
  console.log("Upgrading WithdrawalGuardian");

  const ethers = hre.ethers;
  const upgrades = hre.upgrades;
  const ProxyAdmin = await hre.artifacts.readArtifact("ProxyAdmin");
  const proxyAdmin = new ethers.utils.Interface(ProxyAdmin.abi);

  const proxy = versions[config.oldTag].contracts.WithdrawalGuardianProxy;

  const WithdrawalGuardian = await ethers.getContractFactory("WithdrawalGuardian");

  if (config.execute) {
    const newImplementation = await upgrades.prepareUpgrade(proxy as string, WithdrawalGuardian);
    console.log("New logic deployed to: ", newImplementation);

    await tryVerify(hre, newImplementation, "contracts/utils/WithdrawalGuardian.sol:WithdrawalGuardian", []);

    const upgradeABI = proxyAdmin.encodeFunctionData("upgrade", [proxy, newImplementation]);
    await proposeTx(addresses.proxyAdminAddress, upgradeABI, "Upgrade WithdrawalGuardian", config, addresses);

    versions[config.newTag].contracts.WithdrawalGuardian = newImplementation;

    console.log("WithdrawalGuardian upgraded. New implementation address: ", newImplementation);
  }
};

const deployWithdrawalGuardian = async (
  hre: HardhatRuntimeEnvironment,
  config: IUpgradeConfig,
  versions: IVersions,
  addresses: IAddresses,
) => {
  console.log("Deploying WithdrawalGuardian");

  const ethers = hre.ethers;
  const upgrades = hre.upgrades;
  const provider = ethers.provider;

  const poolFactoryProxy = versions[config.newTag].contracts.PoolFactoryProxy;

  if (!poolFactoryProxy) return console.warn("PoolFactoryProxy missing... skipping.");

  const WithdrawalGuardian = await ethers.getContractFactory("WithdrawalGuardian");
  const initParams = [poolFactoryProxy, WITHDRAWAL_DELAY];

  if (config.execute) {
    const withdrawalGuardian = await upgrades.deployProxy(WithdrawalGuardian, initParams);
    await withdrawalGuardian.deployed();
    const withdrawalGuardianProxy = withdrawalGuardian.address;

    // Retry with delay for RPC propagation
    let withdrawalGuardianImplementationAddress: string | undefined;
    for (let i = 0; i < 5; i++) {
      try {
        withdrawalGuardianImplementationAddress = await getImplementationAddress(provider, withdrawalGuardianProxy);
        break;
      } catch (e) {
        console.log(`Attempt ${i + 1}/5: Waiting for proxy to be indexed...`);
        await new Promise((resolve) => setTimeout(resolve, 5000));
      }
    }
    if (!withdrawalGuardianImplementationAddress) {
      throw new Error(`Failed to get implementation address for proxy at ${withdrawalGuardianProxy} after retries`);
    }

    await tryVerify(
      hre,
      withdrawalGuardianImplementationAddress,
      "contracts/utils/WithdrawalGuardian.sol:WithdrawalGuardian",
      [],
    );

    versions[config.newTag].contracts.WithdrawalGuardianProxy = withdrawalGuardianProxy;
    versions[config.newTag].contracts.WithdrawalGuardian = withdrawalGuardianImplementationAddress;

    console.log("WithdrawalGuardianProxy deployed to: ", withdrawalGuardianProxy);
    console.log("WithdrawalGuardian implementation: ", withdrawalGuardianImplementationAddress);

    // Add the guardian to PoolFactory's receiverWhitelist so depositors can lock tokens
    // without triggering their pool exit cooldown.
    const PoolFactory = await hre.artifacts.readArtifact("PoolFactory");
    const addReceiverWhitelistTxData = new ethers.utils.Interface(PoolFactory.abi).encodeFunctionData(
      "addReceiverWhitelist",
      [withdrawalGuardianProxy],
    );
    await proposeTx(
      poolFactoryProxy,
      addReceiverWhitelistTxData,
      "Add WithdrawalGuardian to PoolFactory receiverWhitelist",
      config,
      addresses,
    );
  }
};
