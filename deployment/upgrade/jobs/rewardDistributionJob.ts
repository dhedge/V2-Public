import { BigNumberish } from "ethers";
import { HardhatRuntimeEnvironment } from "hardhat/types";

import { tryVerify } from "../../deploymentHelpers";
import { Address, IAddresses, IFileNames, IJob, IUpgradeConfig, IVersions } from "../../types";

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
    const Contract = await ethers.getContractFactory("RewardDistribution");
    if (!addresses.rewardDistribution) {
      console.warn("RewardDistribution constructor args are not configured. Skipping.");
      return;
    }
    const args: [Address, BigNumberish] = [
      addresses.rewardDistribution.token,
      addresses.rewardDistribution.amountPerSecond,
    ];
    const rewardDistributionContract = await Contract.deploy(...args);
    await rewardDistributionContract.deployed();

    await tryVerify(
      hre,
      rewardDistributionContract.address,
      "contracts/distribution/RewardDistribution.sol:RewardDistribution",
      args,
    );

    versions[config.newTag].contracts.RewardDistribution = rewardDistributionContract.address;
    console.log("RewardDistribution deployed at ", rewardDistributionContract.address);

    await rewardDistributionContract.setWhitelistedPools(addresses.rewardDistribution.whitelistedPools);
    console.log(`Whitelisted pools set to: ${addresses.rewardDistribution.whitelistedPools.join(", ")}`);

    const transferOwnershipTx = await rewardDistributionContract.transferOwnership(addresses.protocolDaoAddress);
    await transferOwnershipTx.wait(5);
    console.log("Ownership transferred to", addresses.protocolDaoAddress);
  }
};
