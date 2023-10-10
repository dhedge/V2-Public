import { HardhatRuntimeEnvironment } from "hardhat/types";
import { getImplementationAddress } from "@openzeppelin/upgrades-core";
import { proposeTx, tryVerify } from "../../deploymentHelpers";
import { IJob, IProposeTxProperties, IUpgradeConfig, IVersions, IFileNames } from "../../types";

export const nftTrackerJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  // TODO: This optimally should not be mutated
  versions: IVersions,
  _: IFileNames,
  addresses: IProposeTxProperties,
) => {
  const ethers = hre.ethers;
  const upgrades = hre.upgrades;

  const dhedgeNftTrackerStorageProxy = versions[config.newTag].contracts.DhedgeNftTrackerStorageProxy;
  const poolFactoryProxy = versions[config.newTag].contracts.PoolFactoryProxy;

  if (!poolFactoryProxy) {
    console.warn("PoolFactory not deployed: skipping.");
    return;
  }

  if (config.execute) {
    if (!dhedgeNftTrackerStorageProxy) {
      console.log("Will deploy DhedgeNftTrackerStorage");

      const DhedgeNftTrackerStorage = await ethers.getContractFactory("DhedgeNftTrackerStorage");
      const dhedgeNftTrackerStorageProxy = await upgrades.deployProxy(DhedgeNftTrackerStorage, [poolFactoryProxy]);
      await dhedgeNftTrackerStorageProxy.deployed();

      const dhedgeNftTrackerStorageImplementation = await getImplementationAddress(
        ethers.provider,
        dhedgeNftTrackerStorageProxy.address,
      );

      console.log("DhedgeNftTrackerStorageProxy deployed at ", dhedgeNftTrackerStorageProxy.address);
      console.log("DhedgeNftTrackerStorageImpl deployed at ", dhedgeNftTrackerStorageImplementation);

      console.log("implInitializer");
      const dhedgeStakingV2Impl = DhedgeNftTrackerStorage.attach(dhedgeNftTrackerStorageImplementation);
      await dhedgeStakingV2Impl.implInitializer();

      await tryVerify(
        hre,
        dhedgeNftTrackerStorageImplementation,
        "contracts/utils/tracker/DhedgeNftTrackerStorage.sol:DhedgeNftTrackerStorage",
        [],
      );

      console.log("Transferring ownership");

      await dhedgeNftTrackerStorageProxy.transferOwnership(addresses.protocolDaoAddress);

      versions[config.newTag].contracts.DhedgeNftTrackerStorageProxy = dhedgeNftTrackerStorageProxy.address;
      versions[config.newTag].contracts.DhedgeNftTrackerStorage = dhedgeNftTrackerStorageImplementation;
    }
    // Otherwise just upgrade the implementation
    else {
      console.log("Will upgrade DhedgeNftTrackerStorage");
      const DhedgeNftTrackerStorage = await ethers.getContractFactory("DhedgeNftTrackerStorage");
      const dhedgeNftTrackerStorage = await upgrades.prepareUpgrade(
        dhedgeNftTrackerStorageProxy,
        DhedgeNftTrackerStorage,
      );
      console.log("dhedgeNftTrackerStorage deployed to: ", dhedgeNftTrackerStorage);

      console.log("implInitializer");
      const dhedgeNftTrackerStorageImpl = DhedgeNftTrackerStorage.attach(dhedgeNftTrackerStorage);
      await dhedgeNftTrackerStorageImpl.implInitializer();

      await tryVerify(
        hre,
        dhedgeNftTrackerStorage,
        "contracts/utils/tracker/DhedgeNftTrackerStorage.sol:DhedgeNftTrackerStorage",
        [],
      );

      const ProxyAdmin = await hre.artifacts.readArtifact("ProxyAdmin");
      const proxyAdmin = new ethers.utils.Interface(ProxyAdmin.abi);

      const upgradeABI = proxyAdmin.encodeFunctionData("upgrade", [
        dhedgeNftTrackerStorageProxy,
        dhedgeNftTrackerStorage,
      ]);
      await proposeTx(addresses.proxyAdminAddress, upgradeABI, "Upgrade DhedgeNftTrackerStorage", config, addresses);

      versions[config.newTag].contracts.DhedgeNftTrackerStorage = dhedgeNftTrackerStorage;
      console.log("dhedgeNftTrackerStorageImpl deployed at ", dhedgeNftTrackerStorage);
    }
  }
};
