import { BigNumberish } from "ethers";
import { HardhatRuntimeEnvironment } from "hardhat/types";

import { proposeTx, tryVerify } from "../../deploymentHelpers";
import { Address, IAddresses, IFileNames, IJob, IUpgradeConfig, IVersions } from "../../types";

const INDEX_TO_DEPLOY = 3;

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

    // Can start accruing straight after deployment, if 2nd argument is not 0
    const args: [Address, BigNumberish] = [addresses.rewardDistribution[INDEX_TO_DEPLOY].token, 0];
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

    // If deployment was made with rewardAmountPerSecond == 0, will start accruding rewards once tx is executed
    await proposeTx(
      rewardDistributionContract.address,
      rewardDistributionContract.interface.encodeFunctionData("launch", [
        addresses.rewardDistribution[INDEX_TO_DEPLOY].amountPerSecond,
      ]),
      "Start accruing rewards",
      config,
      addresses,
    );
  }
};
