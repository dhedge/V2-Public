import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTransactions } from "../../../helpers/safe";
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

  // One proposal for the whole diff: swapping a caller out for another is then atomic, so there is no
  // nonce in between where the outgoing one is already revoked and the incoming one is not yet live.
  const transactions = [
    ...addedAddresses.map((address) => [address, true] as const),
    ...removedAddresses.map((address) => [address, false] as const),
  ].map(([address, authorized]) => ({
    to: ondoGMSwapProxy,
    data: ondoGMSwapContract.interface.encodeFunctionData("setAuthorizedCaller", [address, authorized]),
    value: "0",
  }));

  if (transactions.length === 0) {
    return console.log("Authorized callers already match the config: nothing to propose.");
  }

  if (config.execute) {
    await proposeTransactions(transactions, "OndoGMSwap - Update authorized callers", config, addresses);

    versions[config.newTag].config.ondoGMSwap = { authorizedCallers: newAddresses };
  }
};
