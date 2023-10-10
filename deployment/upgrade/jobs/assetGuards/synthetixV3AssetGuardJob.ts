import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx, tryVerify } from "../../../deploymentHelpers";
import { IAddresses, IFileNames, IJob, IUpgradeConfig, IVersions } from "../../../types";
import { AssetType } from "../assetsJob";
import { addOrReplaceGuardInFile } from "../helpers";

export const synthetixV3AssetGuardJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  filenames: IFileNames,
  addresses: IAddresses,
) => {
  console.log("Will deploy SynthetixV3AssetGuard");

  if (config.execute) {
    const ethers = hre.ethers;
    const Governance = await hre.artifacts.readArtifact("Governance");
    const governanceABI = new ethers.utils.Interface(Governance.abi);

    const SynthetixV3AssetGuard = await ethers.getContractFactory("SynthetixV3AssetGuard");
    const synthetixV3AssetGuard = await SynthetixV3AssetGuard.deploy();
    await synthetixV3AssetGuard.deployed();
    const synthetixV3AssetGuardAddress = synthetixV3AssetGuard.address;
    console.log("SynthetixV3AssetGuard deployed at", synthetixV3AssetGuardAddress);
    versions[config.newTag].contracts.SynthetixV3AssetGuard = synthetixV3AssetGuardAddress;

    await tryVerify(
      hre,
      synthetixV3AssetGuardAddress,
      "contracts/guards/assetGuards/synthetixV3/SynthetixV3AssetGuard.sol:SynthetixV3AssetGuard",
      [],
    );

    const assetHandlerAssetType = AssetType["Synthetix V3 Position Asset"];

    await proposeTx(
      versions[config.oldTag].contracts.Governance,
      governanceABI.encodeFunctionData("setAssetGuard", [assetHandlerAssetType, synthetixV3AssetGuardAddress]),
      "setAssetGuard for SynthetixV3AssetGuard",
      config,
      addresses,
    );

    await addOrReplaceGuardInFile(
      filenames.assetGuardsFileName,
      {
        assetType: assetHandlerAssetType,
        guardName: "SynthetixV3AssetGuard",
        guardAddress: synthetixV3AssetGuardAddress,
        description: "Synthetix V3 Position Asset",
      },
      "assetType",
    );
  }
};
