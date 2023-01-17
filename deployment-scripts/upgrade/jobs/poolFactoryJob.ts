import { HardhatRuntimeEnvironment } from "hardhat/types";
import { getImplementationAddress } from "@openzeppelin/upgrades-core";
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

  if (config.execute) {
    if (versions[config.oldTag].contracts.PoolFactoryProxy) {
      console.log("Will upgrade poolfactory");

      const poolFactoryProxy = versions[config.oldTag].contracts.PoolFactoryProxy;
      const ProxyAdmin = await hre.artifacts.readArtifact("ProxyAdmin");
      const proxyAdmin = new ethers.utils.Interface(ProxyAdmin.abi);

      const PoolFactoryContract = await ethers.getContractFactory("PoolFactory");
      const newPoolFactoryLogic = await upgrades.prepareUpgrade(poolFactoryProxy, PoolFactoryContract);
      console.log("New PoolFactory logic deployed to: ", newPoolFactoryLogic);
      const poolFactoryImpl = await ethers.getContractAt("PoolFactory", newPoolFactoryLogic);
      console.log("Initialising Impl");
      try {
        // If this script runs and then fails, on retry,
        // The deploy contract will already be initialised.
        await poolFactoryImpl.implInitializer();
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
      } catch (e: any) {
        if (!e.error.message.includes("contract is already initialized")) {
          throw e;
        }
      }

      await tryVerify(hre, newPoolFactoryLogic, "contracts/PoolFactory.sol:PoolFactory", []);

      const upgradeABI = proxyAdmin.encodeFunctionData("upgrade", [poolFactoryProxy, newPoolFactoryLogic]);
      await proposeTx(addresses.proxyAdminAddress, upgradeABI, "Upgrade Pool Factory", config, addresses);

      versions[config.newTag].contracts.PoolFactory = newPoolFactoryLogic;
    } else {
      console.log("Will deploy poolfactory");

      if (!versions[config.oldTag].contracts.PoolLogic) {
        console.warn("PoolLogic missing.. skipping.");
        return;
      }

      if (!versions[config.oldTag].contracts.PoolManagerLogic) {
        console.warn("PoolManagerLogic missing.. skipping.");
        return;
      }

      if (!versions[config.oldTag].contracts.AssetHandlerProxy) {
        console.warn("AssetHandler missing.. skipping.");
        return;
      }

      let governanceAddress = versions[config.oldTag].contracts.Governance;
      if (!versions[config.oldTag].contracts.Governance) {
        const Governance = await ethers.getContractFactory("Governance");
        const governance = await Governance.deploy();
        await governance.deployed();
        console.log("Governance deployed to:", governance.address);
        versions[config.newTag].contracts.Governance = governance.address;

        const ERC20Guard = await ethers.getContractFactory("ERC20Guard");
        const erc20Guard = await ERC20Guard.deploy();
        await erc20Guard.deployed();
        console.log("ERC20Guard deployed at ", erc20Guard.address);
        versions[config.newTag].contracts.ERC20Guard = erc20Guard.address;

        await governance.setAssetGuard(0, erc20Guard.address);
        await governance.transferOwnership(addresses.protocolDaoAddress);

        await tryVerify(hre, governance.address, "Governance", []);
        await tryVerify(hre, erc20Guard.address, "ERC20Guard", []);

        governanceAddress = governance.address;
      }

      const PoolFactory = await ethers.getContractFactory("PoolFactory");
      const poolFactory = await upgrades.deployProxy(PoolFactory, [
        versions[config.oldTag].contracts.PoolLogic,
        versions[config.oldTag].contracts.PoolManagerLogic,
        versions[config.oldTag].contracts.AssetHandlerProxy,
        addresses.protocolDaoAddress,
        governanceAddress,
      ]);
      await poolFactory.deployed();
      console.log("poolFactory deployed at ", poolFactory.address);

      await poolFactory.setDAOAddress(addresses.protocolTreasuryAddress);
      await poolFactory.transferOwnership(addresses.protocolDaoAddress);

      const poolFactoryImplementation = await getImplementationAddress(ethers.provider, poolFactory.address);
      const poolFactoryImpl = PoolFactory.attach(poolFactoryImplementation);

      // There is a security issue where if we don't initialize the impl someone else can take take ownership
      // Using this they can escalate to destroy the contract.
      try {
        await poolFactoryImpl.implInitializer();
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
      } catch (e: any) {
        if (!e.error.message.includes("already initialized")) {
          console.warn("PoolFactory implementation should be initialised");
          throw e;
        }
      }
      await tryVerify(hre, poolFactory.address, "contracts/PoolFactory.sol:PoolFactory", []);

      versions[config.newTag].contracts.PoolFactoryProxy = poolFactory.address;
      versions[config.newTag].contracts.PoolFactory = poolFactoryImplementation;
    }
  }
};
