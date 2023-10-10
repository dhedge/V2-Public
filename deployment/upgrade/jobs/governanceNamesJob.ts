import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx } from "../../deploymentHelpers";
import { IJob, IProposeTxProperties, IUpgradeConfig, IVersions, IFileNames } from "../../types";
import csv from "csvtojson";

export const governanceNamesJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  // TODO: This optimally should not be mutated
  versions: IVersions,
  filenames: IFileNames,
  addresses: IProposeTxProperties,
) => {
  const ethers = hre.ethers;

  // Governance names
  const csvGovernanceNames = await csv().fromFile(filenames.governanceNamesFileName);

  const Governance = await hre.artifacts.readArtifact("Governance");
  const governanceABI = new ethers.utils.Interface(Governance.abi);
  const governance = await ethers.getContractAt("Governance", versions[config.oldTag].contracts.Governance);

  console.log("Will deploy governancenames");
  for (const csvGovernanceName of csvGovernanceNames) {
    const name = csvGovernanceName.name;
    const destination: string = csvGovernanceName.destination;
    const nameBytes = ethers.utils.formatBytes32String(name);
    const configuredDestination = (await governance.nameToDestination(nameBytes)).toLowerCase();
    if (
      configuredDestination === "0x0000000000000000000000000000000000000000" ||
      destination.toLowerCase() != configuredDestination
    ) {
      console.log(name, "old destination:", configuredDestination, ". New destination:", destination);
      const setAddressesABI = governanceABI.encodeFunctionData("setAddresses", [[[nameBytes, destination]]]);
      if (config.execute) {
        await proposeTx(
          versions[config.oldTag].contracts.Governance,
          setAddressesABI,
          `setAddresses for ${name} to ${destination}`,
          config,
          addresses,
        );
      }
    }
  }
};
