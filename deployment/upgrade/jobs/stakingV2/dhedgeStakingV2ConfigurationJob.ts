import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx } from "../../../deploymentHelpers";
import { IAddresses, IFileNames, IJob, IUpgradeConfig, IVersions } from "../../../types";

export const dhedgeStakingV2ConfigurationJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  _: IFileNames,
  addresses: IAddresses,
) => {
  const ethers = hre.ethers;
  console.log("Will update StakingV2 Config");
  if (config.execute) {
    const stakingProxyAddress = versions[config.newTag].contracts.DhedgeStakingV2Proxy;

    if (!stakingProxyAddress) {
      console.warn("No Staking Proxy Address");
      return;
    }

    if (!addresses.stakingV2) {
      return console.warn(`Staking V2 is not configured for chain ${hre.network}`);
    }

    console.log("Configuring DhedgeStakingV2Proxy");
    const dhedgeStakingV2 = await ethers.getContractAt("DhedgeStakingV2", stakingProxyAddress);
    const currentDhtCap = await dhedgeStakingV2.dhtCap();
    // Check here if the cap has changed
    if (!currentDhtCap.eq(addresses.stakingV2.dhtCap)) {
      const setDhtCapTx = await dhedgeStakingV2.populateTransaction.setDHTCap(addresses.stakingV2.dhtCap);
      if (!setDhtCapTx.data) {
        console.warn("Could not encode dhtCapTx");
      } else {
        await proposeTx(
          stakingProxyAddress,
          setDhtCapTx.data,
          `set StakingV2 dhtCap to ${addresses.stakingV2.dhtCap}`,
          config,
          addresses,
        );
      }
    }

    const rewardParams = await dhedgeStakingV2.rewardParams();
    // Check if emissionsRate has changed
    if (rewardParams.emissionsRate.toNumber() !== addresses.stakingV2.emissionsRate) {
      const { data } = await dhedgeStakingV2.populateTransaction.setEmissionsRate(addresses.stakingV2.emissionsRate);
      if (!data) console.warn("Could not encode setEmissionsRate transaction");
      else
        await proposeTx(
          stakingProxyAddress,
          data,
          `Set StakingV2 emissionsRate to ${addresses.stakingV2.emissionsRate}`,
          config,
          addresses,
        );
    }

    const whitelistedPools = addresses.stakingV2.whitelistedPools;
    for (const stakingPool of whitelistedPools) {
      const poolConfig = await dhedgeStakingV2.getPoolConfiguration(stakingPool.pool);
      console.log("Checking for cap changes for", stakingPool.pool);
      // Check here if the cap has changed
      if (!stakingPool.cap.eq(poolConfig.stakeCap)) {
        console.log("Cap change detected for", stakingPool.pool);
        const configurePoolTx = await dhedgeStakingV2.populateTransaction.configurePool(
          stakingPool.pool,
          stakingPool.cap,
        );

        if (!configurePoolTx.data) {
          console.warn("Could not encode configurePoolTx");
        } else {
          await proposeTx(
            stakingProxyAddress,
            configurePoolTx.data,
            `set StakingV2 pool: ${stakingPool.pool} cap to ${stakingPool.cap}`,
            config,
            addresses,
          );

          console.log("Pool Configured", stakingPool);
        }
      }
    }
  }
};
