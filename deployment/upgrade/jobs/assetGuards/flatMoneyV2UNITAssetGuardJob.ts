import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx, tryVerify } from "../../../deploymentHelpers";
import { IAddresses, IFileNames, IJob, IUpgradeConfig, IVersions } from "../../../types";
import { AssetType } from "../assetsJob";
import { addOrReplaceGuardInFile } from "../helpers";

export const flatMoneyV2UNITAssetGuardJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  filenames: IFileNames,
  addresses: IAddresses,
) => {
  console.log("Will deploy FlatMoneyV2UNITAssetGuard");

  if (config.execute) {
    const ethers = hre.ethers;

    const FlatMoneyV2UNITAssetGuard = await ethers.getContractFactory("FlatMoneyV2UNITAssetGuard");
    const flatMoneyV2UNITAssetGuard = await FlatMoneyV2UNITAssetGuard.deploy();
    await flatMoneyV2UNITAssetGuard.deployed();
    const flatMoneyUNITAssetGuardAddress = flatMoneyV2UNITAssetGuard.address;
    console.log("FlatMoneyV2UNITAssetGuard deployed at", flatMoneyUNITAssetGuardAddress);

    versions[config.newTag].contracts.FlatMoneyV2UNITAssetGuard = flatMoneyUNITAssetGuardAddress;

    await tryVerify(
      hre,
      flatMoneyUNITAssetGuardAddress,
      "contracts/guards/assetGuards/flatMoney/v2/FlatMoneyV2UNITAssetGuard.sol:FlatMoneyV2UNITAssetGuard",
      [],
    );

    const Governance = await hre.artifacts.readArtifact("Governance");
    const assetHandlerAssetType = AssetType["Flat Money V2 UNIT"];
    const setAssetGuardTxData = new ethers.utils.Interface(Governance.abi).encodeFunctionData("setAssetGuard", [
      assetHandlerAssetType,
      flatMoneyUNITAssetGuardAddress,
    ]);

    await proposeTx(
      versions[config.oldTag].contracts.Governance,
      setAssetGuardTxData,
      "setAssetGuard for FlatMoneyV2UNITAssetGuard",
      config,
      addresses,
    );

    const deployedGuard = {
      assetType: assetHandlerAssetType,
      guardName: "FlatMoneyV2UNITAssetGuard",
      guardAddress: flatMoneyUNITAssetGuardAddress,
      description: "Flat Money V2 UNIT Asset Guard",
    };

    await addOrReplaceGuardInFile(filenames.assetGuardsFileName, deployedGuard, "assetType");
  }
};
