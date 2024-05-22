import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx, tryVerify } from "../../../deploymentHelpers";
import { IAddresses, IFileNames, IJob, IUpgradeConfig, IVersions } from "../../../types";
import { AssetType } from "../assetsJob";
import { addOrReplaceGuardInFile } from "../helpers";

export const flatMoneyUNITAssetGuardJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  filenames: IFileNames,
  addresses: IAddresses,
) => {
  console.log("Will deploy FlatMoneyUNITAssetGuard");

  if (config.execute) {
    const ethers = hre.ethers;

    const FlatMoneyUNITAssetGuard = await ethers.getContractFactory("FlatMoneyUNITAssetGuard");
    const flatMoneyUNITAssetGuard = await FlatMoneyUNITAssetGuard.deploy();
    await flatMoneyUNITAssetGuard.deployed();
    const flatMoneyUNITAssetGuardAddress = flatMoneyUNITAssetGuard.address;
    console.log("FlatMoneyUNITAssetGuard deployed at", flatMoneyUNITAssetGuardAddress);

    versions[config.newTag].contracts.FlatMoneyUNITAssetGuard = flatMoneyUNITAssetGuardAddress;

    await tryVerify(
      hre,
      flatMoneyUNITAssetGuardAddress,
      "contracts/guards/assetGuards/flatMoney/FlatMoneyUNITAssetGuard.sol:FlatMoneyUNITAssetGuard",
      [],
    );

    const Governance = await hre.artifacts.readArtifact("Governance");
    const assetHandlerAssetType = AssetType["Flat Money's UNIT"];
    const setAssetGuardTxData = new ethers.utils.Interface(Governance.abi).encodeFunctionData("setAssetGuard", [
      assetHandlerAssetType,
      flatMoneyUNITAssetGuardAddress,
    ]);

    await proposeTx(
      versions[config.oldTag].contracts.Governance,
      setAssetGuardTxData,
      "setAssetGuard for FlatMoneyUNITAssetGuard",
      config,
      addresses,
    );

    const deployedGuard = {
      assetType: assetHandlerAssetType,
      guardName: "FlatMoneyUNITAssetGuard",
      guardAddress: flatMoneyUNITAssetGuardAddress,
      description: "Flat Money UNIT Asset Guard",
    };

    await addOrReplaceGuardInFile(filenames.assetGuardsFileName, deployedGuard, "assetType");
  }
};
