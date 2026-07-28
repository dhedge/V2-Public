import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTransactions } from "../../../deploymentHelpers";
import { IAddresses, IFileNames, IJob, IUpgradeConfig, IVersions } from "../../../types";

export const ondoGMSwapConfigurationJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  _filenames: IFileNames,
  addresses: IAddresses,
) => {
  if (!addresses.ondo?.ondoGMSwap) {
    return console.warn("ondo.ondoGMSwap not configured for ondoGMSwapConfigurationJob: skipping.");
  }

  const ondoGMSwapProxy = versions[config.newTag].contracts.OndoGMSwapProxy;
  if (!ondoGMSwapProxy) {
    return console.warn("OndoGMSwapProxy not found for ondoGMSwapConfigurationJob: skipping.");
  }

  console.log("Will update OndoGMSwap authorized callers");

  const ondoGMSwapContract = await hre.ethers.getContractAt("OndoGMSwap", ondoGMSwapProxy);

  const newAddresses = addresses.ondo.ondoGMSwap.authorizedCallers;
  const existingAddresses = versions[config.newTag].config.ondoGMSwap?.authorizedCallers ?? [];

  // Any that are added to the config are authorised on-chain
  const addedAddresses = newAddresses.filter(
    (newAddress) => !existingAddresses.some((existingAddress) => existingAddress === newAddress),
  );

  // Any that are removed from the config are de-authorised on-chain
  const removedAddresses = existingAddresses.filter(
    (existingAddress) => !newAddresses.some((newAddress) => newAddress === existingAddress),
  );

  console.log("New authorized callers: ", addedAddresses);
  console.log("Removed authorized callers: ", removedAddresses);

  if (config.execute) {
    if (addedAddresses.length !== 0) {
      await proposeTransactions(
        addedAddresses.map((address) => ({
          to: ondoGMSwapProxy,
          data: ondoGMSwapContract.interface.encodeFunctionData("setAuthorizedCaller", [address, true]),
          value: "0",
        })),
        "OndoGMSwap - Add authorized callers",
        config,
        addresses,
      );
    }

    if (removedAddresses.length !== 0) {
      await proposeTransactions(
        removedAddresses.map((address) => ({
          to: ondoGMSwapProxy,
          data: ondoGMSwapContract.interface.encodeFunctionData("setAuthorizedCaller", [address, false]),
          value: "0",
        })),
        "OndoGMSwap - Remove authorized callers",
        config,
        addresses,
      );
    }

    versions[config.newTag].config.ondoGMSwap = { authorizedCallers: newAddresses };
  }
};
