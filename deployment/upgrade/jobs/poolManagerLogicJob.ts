import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx, tryVerify } from "../../deploymentHelpers";
import { IJob, IProposeTxProperties, IUpgradeConfig, IVersions, IFileNames } from "../../types";

// PoolManagerLogic upgrade is broken for Optimism as far as I can tell.
// To upgrade, find an object containing address: 0xbc87Becd9b2AED3E282D352b94B80045946CF4b9 and remove storage records coming after nftMembershipCollectionAddress
// I don't know why it looks at this particular object during upgrade and ignores all next upgrades which are plenty.
// Putting there current storage layout might also do the trick.

export const poolManagerLogicJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  // TODO: This optimally should not be mutated
  versions: IVersions,
  _: IFileNames,
  addresses: IProposeTxProperties,
) => {
  const ethers = hre.ethers;
  const upgrades = hre.upgrades;

  if (config.execute) {
    if (versions[config.oldTag].contracts.PoolManagerLogicProxy) {
      console.log("Will upgrade poolmanagerlogic");

      const oldPooManagerLogicProxy = versions[config.oldTag].contracts.PoolManagerLogicProxy;
      const PoolManagerLogic = await ethers.getContractFactory("PoolManagerLogic");
      const poolManagerLogic = await upgrades.prepareUpgrade(oldPooManagerLogicProxy, PoolManagerLogic);
      console.log("poolManagerLogic deployed to: ", poolManagerLogic);
      versions[config.newTag].contracts.PoolManagerLogic = poolManagerLogic;

      await tryVerify(hre, poolManagerLogic, "contracts/PoolManagerLogic.sol:PoolManagerLogic", []);

      const PoolFactory = await hre.artifacts.readArtifact("PoolFactory");
      const PoolFactoryABI = new ethers.utils.Interface(PoolFactory.abi);
      const setLogicABI = PoolFactoryABI.encodeFunctionData("setLogic", [
        versions[config.newTag].contracts.PoolLogic,
        versions[config.newTag].contracts.PoolManagerLogic,
      ]);
      await proposeTx(
        versions[config.oldTag].contracts.PoolFactoryProxy,
        setLogicABI,
        "Set logic for poolLogic and poolManagerLogic",
        config,
        addresses,
      );
    } else {
      console.log("Will deploy poolmanagerlogic");

      const PoolManagerLogic = await ethers.getContractFactory("PoolManagerLogic");
      const poolManagerLogicProxy = await upgrades.deployProxy(PoolManagerLogic, [], { initializer: false });
      await poolManagerLogicProxy.deployed();
      console.log("poolManagerLogicProxy deployed at ", poolManagerLogicProxy.address);

      const poolManagerLogicAddressX = await ethers.provider.getStorageAt(
        poolManagerLogicProxy.address,
        addresses.implementationStorageAddress,
      );
      const poolManagerLogicAddress = ethers.utils.hexValue(poolManagerLogicAddressX);

      await tryVerify(hre, poolManagerLogicAddress, "contracts/PoolManagerLogic.sol:PoolManagerLogic", []);

      versions[config.newTag].contracts.PoolManagerLogicProxy = poolManagerLogicProxy.address;
      versions[config.newTag].contracts.PoolManagerLogic = poolManagerLogicAddress;
    }
  }
};
