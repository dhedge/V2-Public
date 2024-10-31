import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx, tryVerify } from "../../../deploymentHelpers";
import { IAddresses, IFileNames, IJob, IUpgradeConfig, IVersions } from "../../../types";
import { AssetType } from "../assetsJob";
import { addOrReplaceGuardInFile } from "../helpers";

export const rewardAssetGuardJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  filenames: IFileNames,
  addresses: IAddresses,
) => {
  console.log("Will deploy RewardAssetGuard");
  const rewardAssetSetting = addresses.rewardAssetSetting;

  if (!rewardAssetSetting) {
    return console.warn("rewardAssetSetting not configured for RewardAssetGuard. skipping.");
  }

  if (config.execute) {
    const ethers = hre.ethers;

    const RewardAssetGuard = await ethers.getContractFactory("RewardAssetGuard");
    const rewardAssetGuard = await RewardAssetGuard.deploy(rewardAssetSetting);
    await rewardAssetGuard.deployed();
    const rewardAssetGuardAddress = rewardAssetGuard.address;
    console.log("RewardAssetGuard deployed at", rewardAssetGuardAddress);

    versions[config.newTag].contracts.RewardAssetGuard = rewardAssetGuardAddress;

    await tryVerify(
      hre,
      rewardAssetGuardAddress,
      "contracts/guards/assetGuards/RewardAssetGuard.sol:RewardAssetGuard",
      [rewardAssetSetting],
    );

    const Governance = await hre.artifacts.readArtifact("Governance");
    const governanceABI = new ethers.utils.Interface(Governance.abi);
    const assetHandlerAssetType = AssetType["Reward Asset"];
    const setAssetGuardTxData = governanceABI.encodeFunctionData("setAssetGuard", [
      assetHandlerAssetType,
      rewardAssetGuardAddress,
    ]);

    await proposeTx(
      versions[config.oldTag].contracts.Governance,
      setAssetGuardTxData,
      "setAssetGuard for RewardAssetGuard",
      config,
      addresses,
    );

    const deployedGuard = {
      assetType: assetHandlerAssetType,
      guardName: "RewardAssetGuard",
      guardAddress: rewardAssetGuardAddress,
      description: "Reward Asset Guard",
    };

    await addOrReplaceGuardInFile(filenames.assetGuardsFileName, deployedGuard, "assetType");
  }
};
