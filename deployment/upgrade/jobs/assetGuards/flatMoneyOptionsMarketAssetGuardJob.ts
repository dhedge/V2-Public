import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx, tryVerify } from "../../../deploymentHelpers";
import { IAddresses, IFileNames, IJob, IUpgradeConfig, IVersions } from "../../../types";
import { AssetType } from "../assetsJob";
import { addOrReplaceGuardInFile } from "../helpers";

export const flatMoneyOptionsMarketAssetGuardJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  filenames: IFileNames,
  addresses: IAddresses,
) => {
  console.log("Will deploy FlatMoneyOptionsMarketAssetGuard");

  if (config.execute) {
    const ethers = hre.ethers;

    const FlatMoneyOptionsMarketAssetGuard = await ethers.getContractFactory("FlatMoneyOptionsMarketAssetGuard");
    const flatMoneyOptionsMarketAssetGuard = await FlatMoneyOptionsMarketAssetGuard.deploy();
    await flatMoneyOptionsMarketAssetGuard.deployed();
    const flatMoneyOptionsMarketAssetGuardAddress = flatMoneyOptionsMarketAssetGuard.address;
    console.log("FlatMoneyOptionsMarketAssetGuard deployed at", flatMoneyOptionsMarketAssetGuardAddress);

    versions[config.newTag].contracts.FlatMoneyOptionsMarketAssetGuard = flatMoneyOptionsMarketAssetGuardAddress;

    await tryVerify(
      hre,
      flatMoneyOptionsMarketAssetGuardAddress,
      "contracts/guards/assetGuards/flatMoney/v2/FlatMoneyOptionsMarketAssetGuard.sol:FlatMoneyOptionsMarketAssetGuard",
      [],
    );

    const Governance = await hre.artifacts.readArtifact("Governance");
    const assetHandlerAssetType = AssetType["Flat Money Options NFT Position Asset"];
    const setAssetGuardTxData = new ethers.utils.Interface(Governance.abi).encodeFunctionData("setAssetGuard", [
      assetHandlerAssetType,
      flatMoneyOptionsMarketAssetGuardAddress,
    ]);

    await proposeTx(
      versions[config.oldTag].contracts.Governance,
      setAssetGuardTxData,
      "setAssetGuard for FlatMoneyOptionsMarketAssetGuard",
      config,
      addresses,
    );

    const deployedGuard = {
      assetType: assetHandlerAssetType,
      guardName: "FlatMoneyOptionsMarketAssetGuard",
      guardAddress: flatMoneyOptionsMarketAssetGuardAddress,
      description: "Flat Money Options Market Asset Guard",
    };

    await addOrReplaceGuardInFile(filenames.assetGuardsFileName, deployedGuard, "assetType");
  }
};
