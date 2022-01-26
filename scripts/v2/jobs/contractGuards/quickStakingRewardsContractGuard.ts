import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx, tryVerify } from "../../../Helpers";
import { IDeployedContractGuard, IJob, IUpgradeConfig } from "../types";

export const quickStakingRewardsContractGuard: IJob<IDeployedContractGuard[] | undefined> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  // TODO: This should be types and optimally should not be mutated
  versions: any,
  filenames: {},
  addresses: { protocolDaoAddress: string; quickLpUsdcWethStakingRewardsAddress?: string },
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
      config.execute,
      config.restartnonce,
    );

    return [
      {
        ContractAddress: addresses.quickLpUsdcWethStakingRewardsAddress,
        GuardName: "QuickStakingRewardsGuard",
        GuardAddress: quickStakingRewardsGuard.address,
        Description: "Quick Staking Reward",
      },
    ];
  }
};
