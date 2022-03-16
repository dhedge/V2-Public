import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx, tryVerify } from "../../Helpers";
import { IJob, IProposeTxProperties, IUpgradeConfig, IVersions } from "../../types";

export const poolFactoryJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  // TODO: This optimally should not be mutated
  versions: IVersions,
  // eslint-disable-next-line @typescript-eslint/ban-types
  _: {},
  addresses: IProposeTxProperties,
) => {
  const ethers = hre.ethers;
  const upgrades = hre.upgrades;

  const poolFactoryProxy = versions[config.oldTag].contracts.PoolFactoryProxy;
  const ProxyAdmin = await hre.artifacts.readArtifact("ProxyAdmin");
  const proxyAdmin = new ethers.utils.Interface(ProxyAdmin.abi);

  console.log("Will upgrade poolfactory");
  if (config.execute) {
    const PoolFactoryContract = await ethers.getContractFactory("PoolFactory");
    const newPoolFactoryLogic = await upgrades.prepareUpgrade(poolFactoryProxy, PoolFactoryContract);
    console.log("New PoolFactory logic deployed to: ", newPoolFactoryLogic);
    const poolFactoryImpl = await ethers.getContractAt("PoolFactory", newPoolFactoryLogic);
    console.log("Initialising Impl");
    try {
      // If this script runs and then fails, on retry,
      // The deploy contract will already be initialised.
      await poolFactoryImpl.implInitializer();
    } catch (e) {
      if (!e.error.message.includes("contract is already initialized")) {
        throw e;
      }
    }

    await tryVerify(hre, newPoolFactoryLogic, "contracts/PoolFactory.sol:PoolFactory", []);

    const upgradeABI = proxyAdmin.encodeFunctionData("upgrade", [poolFactoryProxy, newPoolFactoryLogic]);
    await proposeTx(addresses.proxyAdminAddress, upgradeABI, "Upgrade Pool Factory", config, addresses);

    versions[config.newTag].contracts.PoolFactory = newPoolFactoryLogic;
  }
};
