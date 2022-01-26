import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx, tryVerify } from "../../../Helpers";
import { IDeployedAssetGuard, IJob, IUpgradeConfig } from "../types";

export const quickLpAssetGuard: IJob<IDeployedAssetGuard | undefined> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  // TODO: This should be types and optimally should not be mutated
  versions: any,
  filenames: {},
  addresses: { protocolDaoAddress: string; quickStakingRewardsFactoryAddress?: string },
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
      config.execute,
      config.restartnonce,
    );
    return {
      AssetType: 5,
      GuardName: "QuickLPAssetGuard",
      GuardAddress: quickLPAssetGuard.address,
      Description: "Quick LP tokens",
    };
  }
};
