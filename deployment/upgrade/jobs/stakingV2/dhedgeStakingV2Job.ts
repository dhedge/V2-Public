import { getImplementationAddress } from "@openzeppelin/upgrades-core";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DhedgeStakingV2 } from "../../../../types";
import { proposeTx, tryVerify } from "../../../deploymentHelpers";
import { IAddresses, IFileNames, IJob, IUpgradeConfig, IVersions } from "../../../types";

export const dhedgeStakingV2Job: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  _: IFileNames,
  addresses: IAddresses,
) => {
  const ethers = hre.ethers;
  const upgrades = hre.upgrades;

  const dhedgeStakingV2Proxy = versions[config.newTag].contracts.DhedgeStakingV2Proxy;

  console.log("Will deploy DhedgeV2Staking");
  // If we've never deployed staking deploy the proxy and the impl
  if (!dhedgeStakingV2Proxy) {
    console.log("Will deploy DhedgeV2Staking");
    const nftJsonAddress = versions[config.newTag].contracts.DhedgeStakingV2NFTJson;
    if (!nftJsonAddress) {
      console.warn("Please deploy DhedgeStakingV2NFTJson first");
      return;
    }
    if (config.execute) {
      console.log("Creating a new deployment of DhedgeV2Staking");
      const DhedgeStakingV2 = await ethers.getContractFactory("DhedgeStakingV2");
      const dhedgeStakingV2Proxy = (await upgrades.deployProxy(DhedgeStakingV2, [
        addresses.assets.dht,
      ])) as DhedgeStakingV2;
      await dhedgeStakingV2Proxy.deployed();

      const dhedgeStakingV2Implementation = await getImplementationAddress(
        ethers.provider,
        dhedgeStakingV2Proxy.address,
      );

      await tryVerify(
        hre,
        dhedgeStakingV2Implementation,
        "contracts/stakingV2/DhedgeStakingV2.sol:DhedgeStakingV2",
        [],
      );

      console.log("dhedgeStakingV2Proxy deployed at ", dhedgeStakingV2Proxy.address);
      console.log("dhedgeStakingV2Impl deployed at ", dhedgeStakingV2Implementation);

      console.log("setTokenUriGenerator");
      await dhedgeStakingV2Proxy.setTokenUriGenerator(nftJsonAddress);

      console.log("setting dhtCap");

      if (!addresses.stakingV2) return console.log("No stakingV2 config found");

      await dhedgeStakingV2Proxy.setDHTCap(addresses.stakingV2.dhtCap);

      console.log("Configuring Pools", addresses.stakingV2.whitelistedPools);

      for (const stakingPool of addresses.stakingV2.whitelistedPools) {
        await dhedgeStakingV2Proxy.configurePool(stakingPool.pool, stakingPool.cap);
        console.log("Pool Configured", stakingPool);
      }

      await dhedgeStakingV2Proxy.transferOwnership(addresses.protocolDaoAddress);

      const PoolFactory = await hre.artifacts.readArtifact("PoolFactory");
      const poolFactoryABI = new ethers.utils.Interface(PoolFactory.abi);
      const addReceiverWhitelistTxData = poolFactoryABI.encodeFunctionData("addReceiverWhitelist", [
        dhedgeStakingV2Proxy.address,
      ]);
      await proposeTx(
        versions[config.newTag].contracts.PoolFactoryProxy,
        addReceiverWhitelistTxData,
        `add StakingV2 address ${dhedgeStakingV2Proxy.address} to receiverWhitelist in PoolFactory`,
        config,
        addresses,
      );

      versions[config.newTag].contracts.DhedgeStakingV2Proxy = dhedgeStakingV2Proxy.address;
      versions[config.newTag].contracts.DhedgeStakingV2 = dhedgeStakingV2Implementation;
    }
  }
  // Otherwise just upgrade the staking impl
  else {
    console.log("Will upgrade DhedgeV2Staking");
    if (config.execute) {
      console.log("Upgrading DhedgeV2Staking");
      const DhedgeStakingV2 = await ethers.getContractFactory("DhedgeStakingV2");
      const dhedgeStakingV2 = await upgrades.prepareUpgrade(dhedgeStakingV2Proxy, DhedgeStakingV2);
      console.log("dhedgeStakingV2 deployed to: ", dhedgeStakingV2);

      await tryVerify(hre, dhedgeStakingV2, "contracts/stakingV2/DhedgeStakingV2.sol:DhedgeStakingV2", []);

      const ProxyAdmin = await hre.artifacts.readArtifact("ProxyAdmin");
      const proxyAdmin = new ethers.utils.Interface(ProxyAdmin.abi);

      const upgradeABI = proxyAdmin.encodeFunctionData("upgrade", [dhedgeStakingV2Proxy, dhedgeStakingV2]);
      await proposeTx(addresses.proxyAdminAddress, upgradeABI, "Upgrade DhedgeStakingV2", config, addresses);

      versions[config.newTag].contracts.DhedgeStakingV2 = dhedgeStakingV2;
      console.log("dhedgeStakingV2Impl deployed at ", dhedgeStakingV2);
    }
  }
};
