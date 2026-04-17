import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx, tryVerify } from "../../../deploymentHelpers";
import { addOrReplaceGuardInFile } from "../helpers";
import { IJob, IProposeTxProperties, IUpgradeConfig, IVersions, IFileNames } from "../../../types";
import { AssetType } from "../assetsJob";

export const hyperliquidSpotGuardJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  filenames: IFileNames,
  addresses: IProposeTxProperties,
) => {
  const ethers = hre.ethers;
  const Governance = await hre.artifacts.readArtifact("Governance");
  const governanceABI = new ethers.utils.Interface(Governance.abi);

  console.log("Will deploy HyperliquidSpotGuard");

  if (config.execute) {
    const HyperliquidSpotGuard = await ethers.getContractFactory("HyperliquidSpotGuard");
    const hyperliquidSpotGuard = await HyperliquidSpotGuard.deploy();
    await hyperliquidSpotGuard.deployed();
    const hyperliquidSpotGuardAddress = hyperliquidSpotGuard.address;
    console.log("HyperliquidSpotGuard deployed at", hyperliquidSpotGuardAddress);
    versions[config.newTag].contracts.HyperliquidSpotGuard = hyperliquidSpotGuardAddress;

    try {
      await tryVerify(
        hre,
        hyperliquidSpotGuardAddress,
        "contracts/guards/assetGuards/hyperliquid/HyperliquidSpotGuard.sol:HyperliquidSpotGuard",
        [],
      );
    } catch (error) {
      console.error("May have failed to verify HyperliquidSpotGuard:", error);
    }

    const assetType = AssetType["Hyperliquid ERC20 Spot Linked Asset"];

    console.log(`Setting HyperliquidSpotGuard for assetType ${assetType}`);
    const setAssetGuardTxData = governanceABI.encodeFunctionData("setAssetGuard", [
      assetType,
      hyperliquidSpotGuardAddress,
    ]);

    await proposeTx(
      versions[config.oldTag].contracts.Governance,
      setAssetGuardTxData,
      `setAssetGuard for HyperliquidSpotGuard AssetType ${assetType}`,
      config,
      addresses,
    );

    const deployedGuard = {
      assetType,
      guardName: "HyperliquidSpotGuard",
      guardAddress: hyperliquidSpotGuardAddress,
      description: "Hyperliquid Spot Asset Guard",
    };

    await addOrReplaceGuardInFile(filenames.assetGuardsFileName, deployedGuard, "assetType");
  }
};
