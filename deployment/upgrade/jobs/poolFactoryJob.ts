import { HardhatRuntimeEnvironment } from "hardhat/types";
import { getImplementationAddress } from "@openzeppelin/upgrades-core";
import { proposeTx, tryVerify } from "../../deploymentHelpers";
import { IJob, IProposeTxProperties, IUpgradeConfig, IVersions, IFileNames } from "../../types";

export const poolFactoryJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  _: IFileNames,
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

        await governance.transferOwnership(addresses.protocolDaoAddress);

        await tryVerify(hre, governance.address, "contracts/Governance.sol:Governance", []);

        governanceAddress = governance.address;
      }

      const PoolFactory = await ethers.getContractFactory("PoolFactory");
      const poolFactory = await upgrades.deployProxy(PoolFactory, [
        versions[config.oldTag].contracts.PoolLogic,
        versions[config.oldTag].contracts.PoolManagerLogic,
        versions[config.oldTag].contracts.AssetHandlerProxy,
        addresses.protocolTreasuryAddress,
        governanceAddress,
      ]);
      await poolFactory.deployed();
      console.log("poolFactory deployed at ", poolFactory.address);

      await poolFactory.transferOwnership(addresses.protocolDaoAddress);

      const poolFactoryImplementation = await getImplementationAddress(ethers.provider, poolFactory.address);

      await tryVerify(hre, poolFactoryImplementation, "contracts/PoolFactory.sol:PoolFactory", []);

      versions[config.newTag].contracts.PoolFactoryProxy = poolFactory.address;
      versions[config.newTag].contracts.PoolFactory = poolFactoryImplementation;
    }
  }
};
