import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx, tryVerify } from "../../../deploymentHelpers";
import { Address, IAddresses, IFileNames, IJob, IUpgradeConfig, IVersions } from "../../../types";
import { AssetType } from "../assetsJob";
import { addOrReplaceGuardInFile } from "../helpers";

export const synthetixV3PerpsAssetGuardJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  filenames: IFileNames,
  addresses: IAddresses,
) => {
  console.log("Will deploy SynthetixV3PerpsAssetGuard");
  const synthetixV3PerpsWithdrawAsset = addresses.synthetixV3?.perpsWithdrawAsset;

  if (!synthetixV3PerpsWithdrawAsset) {
    return console.warn("No perpsWithdrawAsset config for SynthetixV3PerpsAssetGuard: skipping.");
  }

  if (config.execute) {
    const ethers = hre.ethers;
    const Governance = await hre.artifacts.readArtifact("Governance");
    const governanceABI = new ethers.utils.Interface(Governance.abi);

    const SynthetixV3PerpsAssetGuard = await ethers.getContractFactory("SynthetixV3PerpsAssetGuard");
    const args: [Address] = [synthetixV3PerpsWithdrawAsset];
    const synthetixV3PerpsAssetGuard = await SynthetixV3PerpsAssetGuard.deploy(...args);
    await synthetixV3PerpsAssetGuard.deployed();
    const synthetixV3PerpsAssetGuardAddress = synthetixV3PerpsAssetGuard.address;
    console.log("SynthetixV3PerpsAssetGuard deployed at", synthetixV3PerpsAssetGuardAddress);
    versions[config.newTag].contracts.SynthetixV3PerpsAssetGuard = synthetixV3PerpsAssetGuardAddress;

    await tryVerify(
      hre,
      synthetixV3PerpsAssetGuardAddress,
      "contracts/guards/assetGuards/synthetixV3/SynthetixV3PerpsAssetGuard.sol:SynthetixV3PerpsAssetGuard",
      args,
    );

    const assetHandlerAssetType = AssetType["Synthetix V3 Perps Position Asset"];

    await proposeTx(
      versions[config.oldTag].contracts.Governance,
      governanceABI.encodeFunctionData("setAssetGuard", [assetHandlerAssetType, synthetixV3PerpsAssetGuardAddress]),
      "setAssetGuard for SynthetixV3PerpsAssetGuard",
      config,
      addresses,
    );

    await addOrReplaceGuardInFile(
      filenames.assetGuardsFileName,
      {
        assetType: assetHandlerAssetType,
        guardName: "SynthetixV3PerpsAssetGuard",
        guardAddress: synthetixV3PerpsAssetGuardAddress,
        description: "Synthetix V3 Perps Position Asset",
      },
      "assetType",
    );
  }
};
