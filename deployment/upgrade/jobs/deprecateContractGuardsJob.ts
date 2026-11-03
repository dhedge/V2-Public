import csv from "csvtojson";
import { HardhatRuntimeEnvironment } from "hardhat/types";

import { proposeTransactions } from "../../helpers/safe";
import { IJob, IAddresses, IUpgradeConfig, IVersions, IFileNames, IDeployedContractGuard } from "../../types";
import { removeContractGuardFromFile } from "../../helpers/csv";
import type { MetaTransactionData } from "../../helpers/safe";

type MetaTransactionDataWithGuardedAddress = MetaTransactionData & { guardedAddress: string };

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

  const deprecatedContractGuards: IDeployedContractGuard[] = await csv().fromFile(
    filenames.deprecatedContractGuardsFileName,
  );

  const Governance = await hre.artifacts.readArtifact("Governance");
  const governanceABI = new hre.ethers.utils.Interface(Governance.abi);
  const governance = await hre.ethers.getContractAt("Governance", versions[config.oldTag].contracts.Governance);

  console.log("Will deprecate contract guards in Governance (set to address(0))");

  const transactionsList = await Promise.all(
    deprecatedContractGuards.map<Promise<MetaTransactionDataWithGuardedAddress | undefined>>(
      async (deprecatedContractGuard) => {
        const guardedAddress = deprecatedContractGuard.contractAddress;
        const contractGuardSet = await governance.contractGuards(guardedAddress);

        // Skip if already deprecated (guard is address(0))
        if (contractGuardSet === hre.ethers.constants.AddressZero) {
          console.warn(`Contract ${guardedAddress} already deprecated (address(0)): skipping`);
          return;
        }

        console.log(
          `Deprecating guard ${deprecatedContractGuard.guardName} for ${guardedAddress} / ${deprecatedContractGuard.description}`,
        );

        const setContractGuardTxData = governanceABI.encodeFunctionData("setContractGuard", [
          guardedAddress,
          hre.ethers.constants.AddressZero,
        ]);

        return {
          to: versions[config.oldTag].contracts.Governance,
          value: "0",
          data: setContractGuardTxData,
          guardedAddress,
        };
      },
    ),
  );

  const safeTransactionData = transactionsList.filter(
    (txData): txData is MetaTransactionDataWithGuardedAddress => txData !== undefined,
  );

  if (config.execute && safeTransactionData.length !== 0) {
    for (const { guardedAddress } of safeTransactionData) {
      await removeContractGuardFromFile(filenames.contractGuardsFileName, guardedAddress);
    }
    await proposeTransactions(
      // eslint-disable-next-line @typescript-eslint/no-unused-vars
      safeTransactionData.map(({ guardedAddress, ...txData }) => txData),
      "Deprecate contract guards",
      config,
      addresses,
    );
  } else {
    console.log("Safe transaction data: ", safeTransactionData);
  }
};
