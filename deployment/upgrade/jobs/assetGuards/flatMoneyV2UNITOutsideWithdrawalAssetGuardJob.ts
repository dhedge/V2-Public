import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx, tryVerify } from "../../../deploymentHelpers";
import { IAddresses, IFileNames, IJob, IUpgradeConfig, IVersions } from "../../../types";
import { AssetType } from "../assetsJob";
import { addOrReplaceGuardInFile } from "../helpers";

export const flatMoneyV2UNITOutsideWithdrawalAssetGuardJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  filenames: IFileNames,
  addresses: IAddresses,
) => {
  console.log("Will deploy FlatMoneyV2UNITOutsideWithdrawalAssetGuard");

  const collateral = addresses.flatMoneyOptions?.collateral;
  if (!collateral) {
    return console.warn("Collateral address not configured for FlatMoneyV2UNITOutsideWithdrawalAssetGuard. skipping.");
  }

  if (config.execute) {
    const ethers = hre.ethers;

    const FlatMoneyV2UNITOutsideWithdrawalAssetGuard = await ethers.getContractFactory(
      "FlatMoneyV2UNITOutsideWithdrawalAssetGuard",
    );
    const flatMoneyV2UNITOutsideWithdrawalAssetGuard =
      await FlatMoneyV2UNITOutsideWithdrawalAssetGuard.deploy(collateral);
    await flatMoneyV2UNITOutsideWithdrawalAssetGuard.deployed();
    const guardAddress = flatMoneyV2UNITOutsideWithdrawalAssetGuard.address;
    console.log("FlatMoneyV2UNITOutsideWithdrawalAssetGuard deployed at", guardAddress);

    versions[config.newTag].contracts.FlatMoneyV2UNITOutsideWithdrawalAssetGuard = guardAddress;

    await tryVerify(
      hre,
      guardAddress,
      "contracts/guards/assetGuards/flatMoney/v2/FlatMoneyV2UNITOutsideWithdrawalAssetGuard.sol:FlatMoneyV2UNITOutsideWithdrawalAssetGuard",
      [collateral],
    );

    const Governance = await hre.artifacts.readArtifact("Governance");
    const assetHandlerAssetType = AssetType["Flat Money V2 UNIT"];
    const setAssetGuardTxData = new ethers.utils.Interface(Governance.abi).encodeFunctionData("setAssetGuard", [
      assetHandlerAssetType,
      guardAddress,
    ]);

    await proposeTx(
      versions[config.oldTag].contracts.Governance,
      setAssetGuardTxData,
      "setAssetGuard for FlatMoneyV2UNITOutsideWithdrawalAssetGuard",
      config,
      addresses,
    );

    const deployedGuard = {
      assetType: assetHandlerAssetType,
      guardName: "FlatMoneyV2UNITOutsideWithdrawalAssetGuard",
      guardAddress: guardAddress,
      description: "Flat Money V2 UNIT Outside Withdrawal Asset Guard",
    };

    await addOrReplaceGuardInFile(filenames.assetGuardsFileName, deployedGuard, "assetType");
  }
};
