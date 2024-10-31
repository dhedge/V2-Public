import { BigNumberish } from "ethers";
import { HardhatRuntimeEnvironment } from "hardhat/types";

import { tryVerify } from "../../deploymentHelpers";
import { Address, IAddresses, IFileNames, IJob, IUpgradeConfig, IVersions } from "../../types";

const INDEX_TO_DEPLOY = 2;

export const rewardDistributionJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  _: IFileNames,
  addresses: IAddresses,
) => {
  const ethers = hre.ethers;
  console.log("Will deploy RewardDistribution");
  if (config.execute) {
    const RewardDistribution = await ethers.getContractFactory("RewardDistribution");
    if (!addresses.rewardDistribution) {
      console.warn("RewardDistribution constructor args are not configured. Skipping.");
      return;
    }
    const args: [Address, BigNumberish] = [
      addresses.rewardDistribution[INDEX_TO_DEPLOY].token,
      addresses.rewardDistribution[INDEX_TO_DEPLOY].amountPerSecond,
    ];
    const rewardDistributionContract = await RewardDistribution.deploy(...args);
    await rewardDistributionContract.deployed();

    await tryVerify(
      hre,
      rewardDistributionContract.address,
      "contracts/distribution/RewardDistribution.sol:RewardDistribution",
      args,
    );

    versions[config.newTag].contracts.RewardDistribution = (
      versions[config.newTag].contracts.RewardDistribution || []
    ).concat([rewardDistributionContract.address]);

    console.log("RewardDistribution deployed at ", rewardDistributionContract.address);

    await rewardDistributionContract.setWhitelistedPools(
      addresses.rewardDistribution[INDEX_TO_DEPLOY].whitelistedPools,
    );

    await rewardDistributionContract.transferOwnership(addresses.protocolDaoAddress);
    console.log("Ownership transferred to", addresses.protocolDaoAddress);
  }
};
