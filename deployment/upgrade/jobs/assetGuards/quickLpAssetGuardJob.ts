import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx, tryVerify } from "../../../deploymentHelpers";
import { addOrReplaceGuardInFile } from "../helpers";
import { IJob, IProposeTxProperties, IUpgradeConfig, IVersions } from "../../../types";

export const quickLpAssetGuardJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  filenames: { assetGuardsFileName: string },
  addresses: { quickStakingRewardsFactoryAddress?: string } & IProposeTxProperties,
) => {
  if (!addresses.quickStakingRewardsFactoryAddress) {
    console.warn("quickStakingRewardsFactoryAddress not configured for quickLpAssetGuard: skipping.");
    return;
  }

  const ethers = hre.ethers;
  const Governance = await hre.artifacts.readArtifact("Governance");
  const governanceABI = new ethers.utils.Interface(Governance.abi);

  console.log("Will deploy quicklpassetguard");
  if (config.execute) {
    const QuickLPAssetGuard = await ethers.getContractFactory("QuickLPAssetGuard");
    const quickLPAssetGuard = await QuickLPAssetGuard.deploy(addresses.quickStakingRewardsFactoryAddress);
    await quickLPAssetGuard.deployed();
    console.log("quickLPAssetGuard deployed at", quickLPAssetGuard.address);
    versions[config.newTag].contracts.QuickLPAssetGuard = quickLPAssetGuard.address;

    await tryVerify(
      hre,
      quickLPAssetGuard.address,
      "contracts/guards/assetGuards/QuickLPAssetGuard.sol:QuickLPAssetGuard",
      [addresses.quickStakingRewardsFactoryAddress],
    );

    await quickLPAssetGuard.transferOwnership(addresses.protocolDaoAddress);
    const setAssetGuardABI = governanceABI.encodeFunctionData("setAssetGuard", [5, quickLPAssetGuard.address]);
    await proposeTx(
      versions[config.oldTag].contracts.Governance,
      setAssetGuardABI,
      "setAssetGuard for quickLPAssetGuard",
      config,
      addresses,
    );

    const deployedGuard = {
      assetType: 5,
      guardName: "QuickLPAssetGuard",
      guardAddress: quickLPAssetGuard.address,
      description: "Quick LP tokens",
    };

    await addOrReplaceGuardInFile(filenames.assetGuardsFileName, deployedGuard, "assetType");
  }
};
