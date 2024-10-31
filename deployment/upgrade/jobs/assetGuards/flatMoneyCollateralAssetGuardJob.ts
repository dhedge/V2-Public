import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx, tryVerify } from "../../../deploymentHelpers";
import { IAddresses, IFileNames, IJob, IUpgradeConfig, IVersions } from "../../../types";
import { AssetType } from "../assetsJob";
import { addOrReplaceGuardInFile } from "../helpers";

export const flatMoneyCollateralAssetGuardJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  filenames: IFileNames,
  addresses: IAddresses,
) => {
  console.log("Will deploy FlatMoneyCollateralAssetGuard");
  const delayedOrder = addresses.flatMoney?.delayedOrder;

  if (!delayedOrder) {
    return console.warn("DelayedOrder address not configured for FlatMoneyCollateralAssetGuard. skipping.");
  }

  if (config.execute) {
    const ethers = hre.ethers;

    const FlatMoneyCollateralAssetGuard = await ethers.getContractFactory("FlatMoneyCollateralAssetGuard");
    const flatMoneyCollateralAssetGuard = await FlatMoneyCollateralAssetGuard.deploy(delayedOrder);
    await flatMoneyCollateralAssetGuard.deployed();
    const flatMoneyCollateralAssetGuardAddress = flatMoneyCollateralAssetGuard.address;
    console.log("FlatMoneyCollateralAssetGuard deployed at", flatMoneyCollateralAssetGuardAddress);

    versions[config.newTag].contracts.FlatMoneyCollateralAssetGuard = flatMoneyCollateralAssetGuardAddress;

    await tryVerify(
      hre,
      flatMoneyCollateralAssetGuardAddress,
      "contracts/guards/assetGuards/flatMoney/FlatMoneyCollateralAssetGuard.sol:FlatMoneyCollateralAssetGuard",
      [delayedOrder],
    );

    const Governance = await hre.artifacts.readArtifact("Governance");
    const assetHandlerAssetType = AssetType["Flat Money's Collateral"];
    const setAssetGuardTxData = new ethers.utils.Interface(Governance.abi).encodeFunctionData("setAssetGuard", [
      assetHandlerAssetType,
      flatMoneyCollateralAssetGuardAddress,
    ]);

    await proposeTx(
      versions[config.oldTag].contracts.Governance,
      setAssetGuardTxData,
      "setAssetGuard for FlatMoneyCollateralAssetGuard",
      config,
      addresses,
    );

    const deployedGuard = {
      assetType: assetHandlerAssetType,
      guardName: "FlatMoneyCollateralAssetGuard",
      guardAddress: flatMoneyCollateralAssetGuardAddress,
      description: "Flat Money Collateral Asset Guard",
    };

    await addOrReplaceGuardInFile(filenames.assetGuardsFileName, deployedGuard, "assetType");
  }
};
