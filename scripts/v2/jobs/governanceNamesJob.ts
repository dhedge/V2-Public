import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx, tryVerify } from "../../Helpers";
import { IJob, IUpgradeConfig } from "../types";
const csv = require("csvtojson");

export const governanceNamesJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  // TODO: This should be types and optimally should not be mutated
  versions: any,
  filenames: { governanceNamesFileName: string },
  _addresses: {},
) => {
  const ethers = hre.ethers;

  // Governance names
  const csvGovernanceNames = await csv().fromFile(filenames.governanceNamesFileName);

  const Governance = await hre.artifacts.readArtifact("Governance");
  const governanceABI = new ethers.utils.Interface(Governance.abi);
  const governance = await ethers.getContractAt("Governance", versions[config.oldTag].contracts.Governance);

  console.log("Will deploy governancenames");
  for (const csvGovernanceName of csvGovernanceNames) {
    const name = csvGovernanceName.Name;
    const destination = csvGovernanceName.Destination;
    const nameBytes = ethers.utils.formatBytes32String(name);
    const configuredDestination = await governance.nameToDestination(nameBytes);

    if (configuredDestination === "0x0000000000000000000000000000000000000000") {
      const setAddressesABI = governanceABI.encodeFunctionData("setAddresses", [[[nameBytes, destination]]]);
      await proposeTx(
        versions[config.oldTag].contracts.Governance,
        setAddressesABI,
        `setAddresses for ${name} to ${destination}`,
        config.execute,
        config.restartnonce,
      );
    }
  }
};
