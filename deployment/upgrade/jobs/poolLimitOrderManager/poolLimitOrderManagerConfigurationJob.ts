import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTransactions } from "../../../deploymentHelpers";
import { IAddresses, IFileNames, IJob, IUpgradeConfig, IVersions } from "../../../types";

export const poolLimitOrderManagerConfigurationJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  _filenames: IFileNames,
  addresses: IAddresses,
) => {
  console.log("Will update PoolLimitOrderManager configuration");

  const poolLimitOrderManagerProxy = versions[config.newTag].contracts.PoolLimitOrderManagerProxy;

  const poolLimitOrderManagerContract = await hre.ethers.getContractAt(
    "PoolLimitOrderManager",
    poolLimitOrderManagerProxy,
  );

  const newAddresses = addresses.poolLimitOrderManager.authorizedKeeperAddresses;
  const existingAddresses = versions[config.newTag].config.poolLimitOrderManager?.authorizedKeeperAddresses ?? [];

  // Any that are added to the config are added to the whitelist
  const addedAddresses = newAddresses.filter(
    (newAddress) => !existingAddresses.some((existingAddress) => existingAddress === newAddress),
  );

  // Any that are removed from the config are removed from the whitelist
  const removedAddresses = existingAddresses.filter(
    (existingAddress) => !newAddresses.some((newVault) => newVault === existingAddress),
  );

  console.log("New authorized keepers: ", addedAddresses);
  console.log("Removed authorized keepers: ", removedAddresses);

  if (config.execute) {
    if (addedAddresses.length !== 0) {
      await proposeTransactions(
        addedAddresses.map((address) => ({
          to: poolLimitOrderManagerProxy,
          data: poolLimitOrderManagerContract.interface.encodeFunctionData("addAuthorizedKeeper", [address]),
          value: "0",
        })),
        "PoolLimitOrderManager - Add new authorized keepers",
        config,
        addresses,
      );
    }

    if (removedAddresses.length !== 0) {
      await proposeTransactions(
        removedAddresses.map((address) => ({
          to: poolLimitOrderManagerProxy,
          data: poolLimitOrderManagerContract.interface.encodeFunctionData("removeAuthorizedKeeper", [address]),
          value: "0",
        })),
        "PoolLimitOrderManager - Remove authorized keepers",
        config,
        addresses,
      );
    }

    versions[config.newTag].config.poolLimitOrderManager.authorizedKeeperAddresses = newAddresses;
  }
};
