import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx, tryVerify } from "../../../deploymentHelpers";
import { IAddresses, IFileNames, IJob, IUpgradeConfig, IVersions } from "../../../types";
import { AssetType } from "../assetsJob";
import { addOrReplaceGuardInFile } from "../helpers";

export const flatMoneyV2PerpMarketAssetGuardJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  filenames: IFileNames,
  addresses: IAddresses,
) => {
  console.log("Will deploy FlatMoneyV2PerpMarketAssetGuard");

  if (config.execute) {
    const ethers = hre.ethers;

    const FlatMoneyV2PerpMarketAssetGuard = await ethers.getContractFactory("FlatMoneyV2PerpMarketAssetGuard");
    const flatMoneyV2PerpMarketAssetGuard = await FlatMoneyV2PerpMarketAssetGuard.deploy();
    await flatMoneyV2PerpMarketAssetGuard.deployed();
    const flatMoneyOptionsMarketAssetGuardAddress = flatMoneyV2PerpMarketAssetGuard.address;
    console.log("FlatMoneyV2PerpMarketAssetGuard deployed at", flatMoneyOptionsMarketAssetGuardAddress);

    versions[config.newTag].contracts.FlatMoneyV2PerpMarketAssetGuard = flatMoneyOptionsMarketAssetGuardAddress;

    await tryVerify(
      hre,
      flatMoneyOptionsMarketAssetGuardAddress,
      "contracts/guards/assetGuards/flatMoney/v2/FlatMoneyV2PerpMarketAssetGuard.sol:FlatMoneyV2PerpMarketAssetGuard",
      [],
    );

    const Governance = await hre.artifacts.readArtifact("Governance");
    const assetHandlerAssetType = AssetType["Flat Money V2 Perp NFT Position Asset"];
    const setAssetGuardTxData = new ethers.utils.Interface(Governance.abi).encodeFunctionData("setAssetGuard", [
      assetHandlerAssetType,
      flatMoneyOptionsMarketAssetGuardAddress,
    ]);

    await proposeTx(
      versions[config.oldTag].contracts.Governance,
      setAssetGuardTxData,
      "setAssetGuard for FlatMoneyV2PerpMarketAssetGuard",
      config,
      addresses,
    );

    const deployedGuard = {
      assetType: assetHandlerAssetType,
      guardName: "FlatMoneyV2PerpMarketAssetGuard",
      guardAddress: flatMoneyOptionsMarketAssetGuardAddress,
      description: "Flat Money V2 Perp Market Asset Guard",
    };

    await addOrReplaceGuardInFile(filenames.assetGuardsFileName, deployedGuard, "assetType");
  }
};
