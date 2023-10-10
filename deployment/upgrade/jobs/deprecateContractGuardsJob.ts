import csv from "csvtojson";
import { HardhatRuntimeEnvironment } from "hardhat/types";

import { proposeTx } from "../../deploymentHelpers";
import { IJob, IAddresses, IUpgradeConfig, IVersions, IFileNames, IDeployedContractGuard } from "../../types";
import { removeContractGuardFromFile } from "./helpers";

export const deprecateContractGuardsJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  filenames: IFileNames,
  addresses: IAddresses,
) => {
  if (!filenames.deprecatedContractGuardsFileName) {
    return console.warn("No deprecatedContractGuardsFileName configured: skipping");
  }

  // This is a workaround because Governance's setContractGuard doesn't accept address(0) as a guard address
  if (!versions[config.oldTag].contracts.ClosedContractGuard) {
    return console.warn("ClosedContractGuard not found: skipping");
  }

  const emptyContractGuardAddress = versions[config.oldTag].contracts.ClosedContractGuard;

  const deprecatedContractGuards: IDeployedContractGuard[] = await csv().fromFile(
    filenames.deprecatedContractGuardsFileName,
  );

  const Governance = await hre.artifacts.readArtifact("Governance");
  const governanceABI = new hre.ethers.utils.Interface(Governance.abi);
  const governance = await hre.ethers.getContractAt("Governance", versions[config.oldTag].contracts.Governance);

  console.log("Will remove deprecated guards from Governance");

  for (const deprecatedContractGuard of deprecatedContractGuards) {
    const guardedAddress = deprecatedContractGuard.contractAddress;
    const contractGuardSet = await governance.contractGuards(guardedAddress);
    const guardAddress = deprecatedContractGuard.guardAddress;

    if (contractGuardSet.toLowerCase() !== guardAddress.toLowerCase()) {
      console.warn(`Guard ${guardAddress} is not set for ${guardedAddress}: skipping`);
      continue;
    }

    console.log(
      `Removing guard ${deprecatedContractGuard.guardName} for ${guardedAddress} / ${deprecatedContractGuard.description}`,
    );

    if (config.execute) {
      const setContractGuardTxData = governanceABI.encodeFunctionData("setContractGuard", [
        guardedAddress,
        emptyContractGuardAddress,
      ]);

      await proposeTx(
        versions[config.oldTag].contracts.Governance,
        setContractGuardTxData,
        `setContractGuard for ${guardedAddress} to ClosedContractGuard`,
        config,
        addresses,
      );
    }

    await removeContractGuardFromFile(filenames.contractGuardsFileName, guardedAddress);
  }
};
