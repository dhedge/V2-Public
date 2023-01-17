import { HardhatRuntimeEnvironment } from "hardhat/types";

import { tryVerify } from "../../Helpers";
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
    const args: [Address, number] = [addresses.rewardDistribution.token, addresses.rewardDistribution.amountPerSecond];
    const contract = await Contract.deploy(...args);
    await contract.deployed();

    await tryVerify(hre, contract.address, "contracts/distribution/RewardDistribution.sol:RewardDistribution", args);

    versions[config.newTag].contracts.RewardDistribution = contract.address;
    console.log("RewardDistribution deployed at ", contract.address);
  }
};
