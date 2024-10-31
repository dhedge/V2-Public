import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx, tryVerify } from "../../../deploymentHelpers";
import { IAddresses, IFileNames, IJob, IUpgradeConfig, IVersions } from "../../../types";
import { AssetType } from "../assetsJob";
import { addOrReplaceGuardInFile } from "../helpers";

export const flatMoneyPerpMarketAssetGuardJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  filenames: IFileNames,
  addresses: IAddresses,
) => {
  console.log("Will deploy FlatMoneyPerpMarketAssetGuard");

  if (config.execute) {
    const ethers = hre.ethers;

    const FlatMoneyPerpMarketAssetGuard = await ethers.getContractFactory("FlatMoneyPerpMarketAssetGuard");
    const flatMoneyPerpMarketAssetGuard = await FlatMoneyPerpMarketAssetGuard.deploy();
    await flatMoneyPerpMarketAssetGuard.deployed();
    const flatMoneyPerpMarketAssetGuardAddress = flatMoneyPerpMarketAssetGuard.address;
    console.log("FlatMoneyPerpMarketAssetGuard deployed at", flatMoneyPerpMarketAssetGuardAddress);

    versions[config.newTag].contracts.FlatMoneyPerpMarketAssetGuard = flatMoneyPerpMarketAssetGuardAddress;

    await tryVerify(
      hre,
      flatMoneyPerpMarketAssetGuardAddress,
      "contracts/guards/assetGuards/flatMoney/FlatMoneyPerpMarketAssetGuard.sol:FlatMoneyPerpMarketAssetGuard",
      [],
    );

    const Governance = await hre.artifacts.readArtifact("Governance");
    const assetHandlerAssetType = AssetType["Flat Money's Leverage Asset"];
    const setAssetGuardTxData = new ethers.utils.Interface(Governance.abi).encodeFunctionData("setAssetGuard", [
      assetHandlerAssetType,
      flatMoneyPerpMarketAssetGuardAddress,
    ]);

    await proposeTx(
      versions[config.oldTag].contracts.Governance,
      setAssetGuardTxData,
      "setAssetGuard for FlatMoneyPerpMarketAssetGuard",
      config,
      addresses,
    );

    const deployedGuard = {
      assetType: assetHandlerAssetType,
      guardName: "FlatMoneyPerpMarketAssetGuard",
      guardAddress: flatMoneyPerpMarketAssetGuardAddress,
      description: "Flat Money Perp Market Asset Guard",
    };

    await addOrReplaceGuardInFile(filenames.assetGuardsFileName, deployedGuard, "assetType");
  }
};
