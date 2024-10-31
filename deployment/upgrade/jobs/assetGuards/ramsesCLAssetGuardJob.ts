import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx, tryVerify } from "../../../deploymentHelpers";
import { IJob, IUpgradeConfig, IVersions, IFileNames, IAddresses } from "../../../types";
import { addOrReplaceGuardInFile } from "../helpers";
import { AssetType } from "../assetsJob";

export const ramsesCLAssetGuardJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  filenames: IFileNames,
  addresses: IAddresses,
) => {
  console.log("Will deploy RamsesCLAssetGuard");
  const ramsesVoter = addresses.ramses?.voter;

  if (!ramsesVoter) {
    return console.warn("RAMSES voter address not configured for RamsesCLAssetGuard. skipping.");
  }
  if (config.execute) {
    const ethers = hre.ethers;
    const Governance = await hre.artifacts.readArtifact("Governance");
    const governanceABI = new ethers.utils.Interface(Governance.abi);

    const RamsesCLAssetGuard = await ethers.getContractFactory("RamsesCLAssetGuard");
    const args: [string] = [ramsesVoter];
    const ramsesCLAssetGuard = await RamsesCLAssetGuard.deploy(...args);
    await ramsesCLAssetGuard.deployed();
    const ramsesCLAssetGuardAddress = ramsesCLAssetGuard.address;
    console.log("RamsesCLAssetGuard deployed at", ramsesCLAssetGuardAddress);

    versions[config.newTag].contracts.RamsesCLAssetGuard = ramsesCLAssetGuardAddress;

    await tryVerify(
      hre,
      ramsesCLAssetGuardAddress,
      "contracts/guards/assetGuards/ramsesCL/RamsesCLAssetGuard.sol:RamsesCLAssetGuard",
      args,
    );
    const assetHandlerAssetType = AssetType["Ramses CL NFT Position Asset"];
    const setAssetGuardABI = governanceABI.encodeFunctionData("setAssetGuard", [
      assetHandlerAssetType,
      ramsesCLAssetGuardAddress,
    ]);

    await proposeTx(
      versions[config.oldTag].contracts.Governance,
      setAssetGuardABI,
      "setAssetGuard for RamsesCLAssetGuard",
      config,
      addresses,
    );

    const deployedGuard = {
      assetType: assetHandlerAssetType,
      guardName: "RamsesCLAssetGuard",
      guardAddress: ramsesCLAssetGuardAddress,
      description: "RamsesCL LP positions",
    };

    await addOrReplaceGuardInFile(filenames.assetGuardsFileName, deployedGuard, "assetType");
  }
};
