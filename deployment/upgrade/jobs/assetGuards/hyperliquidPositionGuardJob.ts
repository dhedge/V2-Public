import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx, tryVerify } from "../../../deploymentHelpers";
import { IAddresses, IFileNames, IJob, IUpgradeConfig, IVersions } from "../../../types";
import { addOrReplaceGuardInFile } from "../helpers";
import { AssetType } from "../assetsJob";

export const hyperliquidPositionGuardJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  filenames: IFileNames,
  addresses: IAddresses,
) => {
  console.log("Will deploy HyperliquidPositionGuard");

  if (config.execute) {
    const ethers = hre.ethers;

    const HyperliquidPositionGuard = await ethers.getContractFactory("HyperliquidPositionGuard");
    const hyperliquidPositionGuard = await HyperliquidPositionGuard.deploy();
    await hyperliquidPositionGuard.deployed();
    const hyperliquidPositionGuardAddress = hyperliquidPositionGuard.address;
    console.log("HyperliquidPositionGuard deployed at", hyperliquidPositionGuardAddress);

    versions[config.newTag].contracts.HyperliquidPositionGuard = hyperliquidPositionGuardAddress;

    try {
      await tryVerify(
        hre,
        hyperliquidPositionGuardAddress,
        "contracts/guards/assetGuards/hyperliquid/HyperliquidPositionGuard.sol:HyperliquidPositionGuard",
        [],
      );
    } catch (error) {
      console.error("May have failed to verify HyperliquidPositionGuard:", error);
    }

    const Governance = await hre.artifacts.readArtifact("Governance");
    const assetHandlerAssetType = AssetType["Hyperliquid Perps Account"];
    const setAssetGuardTxData = new ethers.utils.Interface(Governance.abi).encodeFunctionData("setAssetGuard", [
      assetHandlerAssetType,
      hyperliquidPositionGuardAddress,
    ]);

    await proposeTx(
      versions[config.oldTag].contracts.Governance,
      setAssetGuardTxData,
      "setAssetGuard for HyperliquidPositionGuard",
      config,
      addresses,
    );

    const deployedGuard = {
      assetType: assetHandlerAssetType,
      guardName: "HyperliquidPositionGuard",
      guardAddress: hyperliquidPositionGuardAddress,
      description: "Hyperliquid Position Asset Guard",
    };

    await addOrReplaceGuardInFile(filenames.assetGuardsFileName, deployedGuard, "assetType");
  }
};
