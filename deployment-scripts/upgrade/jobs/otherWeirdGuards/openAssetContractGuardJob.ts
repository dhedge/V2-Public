import csv from "csvtojson";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx, tryVerify, writeCsv } from "../../../Helpers";
import { IJob, INotSureGuard, IUpgradeConfig, IVersions } from "../../../types";

// JBG69 Not sure what this guard is suppose to do
export const openAssetContractGuardJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  // TODO: This optimally should not be mutated
  versions: IVersions,
  filenames: { externalAssetFileName?: string; governanceNamesFileName: string },
) => {
  const ethers = hre.ethers;
  const Governance = await hre.artifacts.readArtifact("Governance");
  const governanceABI = new ethers.utils.Interface(Governance.abi);

  if (!filenames.externalAssetFileName) {
    throw new Error("No externalAssetFileName configured");
  }

  console.log("Will deploy openassetguard");
  if (config.execute) {
    const fileName = filenames.externalAssetFileName;
    const csvAssets = await csv().fromFile(fileName);
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const addresses: any = csvAssets.map((asset) => asset.Address);
    const OpenAssetGuard = await ethers.getContractFactory("OpenAssetGuard");
    const openAssetGuard = await OpenAssetGuard.deploy(addresses);
    await openAssetGuard.deployed();
    console.log("OpenAssetGuard deployed at", openAssetGuard.address);
    versions[config.newTag].contracts.OpenAssetGuard = openAssetGuard.address;

    await tryVerify(hre, openAssetGuard.address, "contracts/guards/assetGuards/OpenAssetGuard.sol:OpenAssetGuard", [
      addresses,
    ]);

    await openAssetGuard.transferOwnership(addresses.protocolDaoAddress);
    const setAddressesABI = governanceABI.encodeFunctionData("setAddresses", [
      [[ethers.utils.formatBytes32String("openAssetGuard"), openAssetGuard.address]],
    ]);
    await proposeTx(
      versions[config.oldTag].contracts.Governance,
      setAddressesABI,
      "setAddresses for openAssetGuard",
      config,
      addresses,
    );
    const openAssetGuardRecord: INotSureGuard = {
      name: "openAssetGuard",
      destination: openAssetGuard.address,
    };
    const csvGovernanceNames = await csv().fromFile(filenames.governanceNamesFileName);

    // Filter out any existing guard
    const withoutOpenAssetGuard = csvGovernanceNames.map(
      (csvGovernanceName: INotSureGuard) => csvGovernanceName.name != openAssetGuardRecord.name,
    );

    writeCsv([...withoutOpenAssetGuard, openAssetGuardRecord], filenames.governanceNamesFileName);
  }
};
