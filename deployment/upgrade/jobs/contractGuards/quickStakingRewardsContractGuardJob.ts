import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx, tryVerify } from "../../../deploymentHelpers";
import { addOrReplaceGuardInFile } from "../helpers";
import { IJob, IProposeTxProperties, IUpgradeConfig, IVersions } from "../../../types";

export const quickStakingRewardsContractGuardJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  filenames: { contractGuardsFileName: string },
  addresses: { quickLpUsdcWethStakingRewardsAddress?: string } & IProposeTxProperties,
) => {
  if (!addresses.quickLpUsdcWethStakingRewardsAddress) {
    console.warn("balancerV2VaultAddress not configured for quickStakingRewardsContractGuard: skipping.");
    return;
  }

  const ethers = hre.ethers;
  const Governance = await hre.artifacts.readArtifact("Governance");
  const governanceABI = new ethers.utils.Interface(Governance.abi);

  console.log("Will deploy quickstakingrewardsguard");
  if (config.execute) {
    const QuickStakingRewardsGuard = await ethers.getContractFactory("QuickStakingRewardsGuard");
    const quickStakingRewardsGuard = await QuickStakingRewardsGuard.deploy();
    await quickStakingRewardsGuard.deployed();
    console.log("quickStakingRewardsGuard deployed at", quickStakingRewardsGuard.address);
    versions[config.newTag].contracts.QuickStakingRewardsGuard = quickStakingRewardsGuard.address;

    await tryVerify(
      hre,
      quickStakingRewardsGuard.address,
      "contracts/guards/contractGuards/QuickStakingRewardsGuard.sol:QuickStakingRewardsGuard",
      [],
    );

    const setContractGuardABI = governanceABI.encodeFunctionData("setContractGuard", [
      addresses.quickLpUsdcWethStakingRewardsAddress,
      quickStakingRewardsGuard.address,
    ]);
    await proposeTx(
      versions[config.oldTag].contracts.Governance,
      setContractGuardABI,
      "setContractGuard for QuickStakingRewardsGuard",
      config,
      addresses,
    );

    const deployedGuard = {
      contractAddress: addresses.quickLpUsdcWethStakingRewardsAddress,
      guardName: "QuickStakingRewardsGuard",
      guardAddress: quickStakingRewardsGuard.address,
      description: "Quick Staking Reward",
    };
    await addOrReplaceGuardInFile(filenames.contractGuardsFileName, deployedGuard, "contractAddress");
  }
};
