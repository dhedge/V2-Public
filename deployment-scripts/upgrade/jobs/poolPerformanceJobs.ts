import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx, tryVerify } from "../../Helpers";
import { IJob, IProposeTxProperties, IUpgradeConfig, IVersions } from "../../types";

export const poolPerformanceJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  // TODO: This optimally should not be mutated
  versions: IVersions,
  // eslint-disable-next-line @typescript-eslint/ban-types
  _filenames: {},
  addresses: IProposeTxProperties,
) => {
  const ethers = hre.ethers;
  const upgrades = hre.upgrades;
  const provider = ethers.provider;
  console.log("Will upgrade poolperformance");

  if (versions[config.oldTag].contracts.PoolPerformanceProxy) {
    // Upgrade PoolPerformance
    if (config.execute) {
      const oldPoolPerformance = versions[config.oldTag].contracts.PoolPerformanceProxy;
      const PoolPerformance = await ethers.getContractFactory("PoolPerformance");
      const poolPerformance = await upgrades.prepareUpgrade(oldPoolPerformance, PoolPerformance);
      console.log("poolPerformance deployed to: ", poolPerformance);

      await tryVerify(hre, poolPerformance, "contracts/PoolPerformance.sol:PoolPerformance", []);

      const ProxyAdmin = await hre.artifacts.readArtifact("ProxyAdmin");
      const proxyAdmin = new ethers.utils.Interface(ProxyAdmin.abi);

      const upgradeABI = proxyAdmin.encodeFunctionData("upgrade", [oldPoolPerformance, poolPerformance]);
      await proposeTx(addresses.proxyAdminAddress, upgradeABI, "Upgrade Pool Performance", config, addresses);

      versions[config.newTag].contracts.PoolPerformance = poolPerformance;
    }
  } else {
    if (config.execute) {
      // Deploy PoolPerformance (is not yet deployed)
      const PoolPerformance = await ethers.getContractFactory("PoolPerformance");
      const poolPerformanceProxy = await upgrades.deployProxy(PoolPerformance, []);
      await poolPerformanceProxy.deployed();
      console.log("poolPerformanceProxy deployed to:", poolPerformanceProxy.address);
      const poolPerformanceAddress = ethers.utils.hexValue(
        await provider.getStorageAt(poolPerformanceProxy.address, addresses.implementationStorageAddress),
      );
      // const poolPerformanceAddress = await proxyAdmin.getProxyImplementation(poolPerformanceProxy.address);
      const poolPerformance = PoolPerformance.attach(poolPerformanceAddress);

      await poolPerformanceProxy.transferOwnership(addresses.protocolDaoAddress);

      await tryVerify(hre, poolPerformance.address, "contracts/PoolPerformance.sol:PoolPerformance", []);

      // Set PoolPerformance address in the Factory
      const PoolFactory = await hre.artifacts.readArtifact("PoolFactory");
      const PoolFactoryABI = new ethers.utils.Interface(PoolFactory.abi);
      const setPoolPerformanceAddressABI = PoolFactoryABI.encodeFunctionData("setPoolPerformanceAddress", [
        poolPerformanceProxy.address,
      ]);

      const poolFactoryProxyAddress = versions[config.oldTag].contracts.PoolFactoryProxy;

      await proposeTx(
        poolFactoryProxyAddress,
        setPoolPerformanceAddressABI,
        `setPoolPerformanceAddress in Factory to ${poolPerformanceAddress}`,
        config,
        addresses,
      );

      // Add to versions file
      versions[config.newTag].contracts.PoolPerformanceProxy = poolPerformanceProxy.address;
      versions[config.newTag].contracts.PoolPerformance = poolPerformanceAddress;
    }
  }
};
