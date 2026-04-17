import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx, tryVerify } from "../../../deploymentHelpers";
import { addOrReplaceGuardInFile } from "../helpers";
import { IJob, IProposeTxProperties, IUpgradeConfig, IVersions, IFileNames } from "../../../types";
import { AssetType } from "../assetsJob";

export const hyperliquidERC20GuardJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  filenames: IFileNames,
  addresses: IProposeTxProperties,
) => {
  if (hre.network.name !== "hyperevm") {
    throw new Error("HyperliquidERC20Guard can only be deployed on HyperEVM");
  }

  const ethers = hre.ethers;
  const Governance = await hre.artifacts.readArtifact("Governance");
  const governanceABI = new ethers.utils.Interface(Governance.abi);

  console.log("Will deploy HyperliquidERC20Guard");

  if (config.execute) {
    const HyperliquidERC20Guard = await ethers.getContractFactory("HyperliquidERC20Guard");
    const hyperliquidERC20Guard = await HyperliquidERC20Guard.deploy();
    await hyperliquidERC20Guard.deployed();
    const hyperliquidERC20GuardAddress = hyperliquidERC20Guard.address;
    console.log("HyperliquidERC20Guard deployed at", hyperliquidERC20GuardAddress);
    versions[config.newTag].contracts.HyperliquidERC20Guard = hyperliquidERC20GuardAddress;

    try {
      await tryVerify(
        hre,
        hyperliquidERC20GuardAddress,
        "contracts/guards/assetGuards/hyperliquid/HyperliquidERC20Guard.sol:HyperliquidERC20Guard",
        [],
      );
    } catch (error) {
      console.error("May have failed to verify HyperliquidERC20Guard:", error);
    }

    const assetType = AssetType["Chainlink direct USD price feed with 8 decimals"];

    console.log(`Setting HyperliquidERC20Guard for assetType ${assetType}`);
    const setAssetGuardTxData = governanceABI.encodeFunctionData("setAssetGuard", [
      assetType,
      hyperliquidERC20GuardAddress,
    ]);

    await proposeTx(
      versions[config.oldTag].contracts.Governance,
      setAssetGuardTxData,
      `setAssetGuard for HyperliquidERC20Guard AssetType ${assetType}`,
      config,
      addresses,
    );

    const deployedGuard = {
      assetType,
      guardName: "HyperliquidERC20Guard",
      guardAddress: hyperliquidERC20GuardAddress,
      description: "Hyperliquid ERC20 Asset Guard",
    };

    await addOrReplaceGuardInFile(filenames.assetGuardsFileName, deployedGuard, "assetType");
  }
};
