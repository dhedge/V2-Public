import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx, tryVerify } from "../../../deploymentHelpers";
import { IJob, IAddresses, IUpgradeConfig, IVersions, IFileNames } from "../../../types";
import { addOrReplaceGuardInFile } from "../helpers";
import { AssetType } from "../assetsJob";

export const fluidTokenAssetGuardJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  filenames: IFileNames,
  addresses: IAddresses,
) => {
  console.log("Will deploy FluidTokenAssetGuard");

  if (config.execute) {
    const ethers = hre.ethers;
    const Governance = await hre.artifacts.readArtifact("Governance");

    const FluidTokenAssetGuard = await ethers.getContractFactory("FluidTokenAssetGuard");
    const fluidTokenAssetGuard = await FluidTokenAssetGuard.deploy();
    await fluidTokenAssetGuard.deployed();
    const guardAddress = fluidTokenAssetGuard.address;
    console.log("FluidTokenAssetGuard deployed at", guardAddress);

    versions[config.newTag].contracts.FluidTokenAssetGuard = guardAddress;

    await tryVerify(
      hre,
      guardAddress,
      "contracts/guards/assetGuards/fluid/FluidTokenAssetGuard.sol:FluidTokenAssetGuard",
      [],
    );

    const assetType = AssetType["Fluid Token"];
    await proposeTx(
      versions[config.oldTag].contracts.Governance,
      new ethers.utils.Interface(Governance.abi).encodeFunctionData("setAssetGuard", [assetType, guardAddress]),
      "setAssetGuard for FluidTokenAssetGuard",
      config,
      addresses,
    );

    const deployedGuard = {
      assetType,
      guardName: "FluidTokenAssetGuard",
      guardAddress,
      description: "Fluid Token",
    };

    await addOrReplaceGuardInFile(filenames.assetGuardsFileName, deployedGuard, "assetType");
  }
};
