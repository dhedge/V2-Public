import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx, tryVerify } from "../../../deploymentHelpers";
import { IAddresses, IFileNames, IJob, IUpgradeConfig, IVersions } from "../../../types";
import { AssetType } from "../assetsJob";
import { addOrReplaceGuardInFile } from "../helpers";

export const compoundV3CometAssetGuardJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  filenames: IFileNames,
  addresses: IAddresses,
) => {
  console.log("Will deploy CompoundV3CometAssetGuard");

  if (config.execute) {
    const ethers = hre.ethers;

    const CompoundV3CometAssetGuard = await ethers.getContractFactory("CompoundV3CometAssetGuard");
    const compoundV3CometAssetGuard = await CompoundV3CometAssetGuard.deploy();
    await compoundV3CometAssetGuard.deployed();
    const compoundV3CometAssetGuardAddress = compoundV3CometAssetGuard.address;
    console.log("CompoundV3CometAssetGuard deployed at", compoundV3CometAssetGuardAddress);

    versions[config.newTag].contracts.CompoundV3CometAssetGuard = compoundV3CometAssetGuardAddress;

    await tryVerify(
      hre,
      compoundV3CometAssetGuardAddress,
      "contracts/guards/assetGuards/CompoundV3CometAssetGuard.sol:CompoundV3CometAssetGuard",
      [],
    );

    const Governance = await hre.artifacts.readArtifact("Governance");
    const assetType = AssetType["Compound V3 Comet Asset"];

    await proposeTx(
      versions[config.oldTag].contracts.Governance,
      new ethers.utils.Interface(Governance.abi).encodeFunctionData("setAssetGuard", [
        assetType,
        compoundV3CometAssetGuardAddress,
      ]),
      "setAssetGuard for CompoundV3CometAssetGuard",
      config,
      addresses,
    );

    const deployedGuard = {
      assetType,
      guardName: "CompoundV3CometAssetGuard",
      guardAddress: compoundV3CometAssetGuardAddress,
      description: "CompoundV3 Comet AssetGuard",
    };

    await addOrReplaceGuardInFile(filenames.assetGuardsFileName, deployedGuard, "assetType");
  }
};
