import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx, tryVerify, writeCsv } from "../../../Helpers";
import { INotSureGuard, IJob, IUpgradeConfig } from "../types";
const csv = require("csvtojson");

// JBG69 Not sure what this guard is suppose to do
export const openAssetContractGuardJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  // TODO: This should be types and optimally should not be mutated
  versions: any,
  filenames: { assetsFileName?: string; governanceNamesFileName: string },
  addresses: {},
) => {
  const ethers = hre.ethers;
  const Governance = await hre.artifacts.readArtifact("Governance");
  const governanceABI = new ethers.utils.Interface(Governance.abi);
  if (!filenames.assetsFileName) {
    throw new Error("No assetFileName configured");
  }

  console.log("Will deploy openassetguard");
  if (config.execute) {
    const fileName = filenames.assetsFileName;
    const csvAssets = await csv().fromFile(fileName);
    let addresses = csvAssets.map((asset: any) => asset.Address);
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
      config.execute,
      config.restartnonce,
    );
    const openAssetGuardRecord: INotSureGuard = {
      Name: "openAssetGuard",
      Destination: openAssetGuard.address,
    };
    const csvGovernanceNames = await csv().fromFile(filenames.governanceNamesFileName);

    // Filter out any existing guard
    const withoutOpenAssetGuard = csvGovernanceNames.map(
      (csvGovernanceName: INotSureGuard) => csvGovernanceName.Name != openAssetGuardRecord.Name,
    );

    writeCsv([...withoutOpenAssetGuard, openAssetGuardRecord], filenames.governanceNamesFileName);
  }
};
