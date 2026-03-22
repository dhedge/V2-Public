import { getImplementationAddress } from "@openzeppelin/upgrades-core";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx, tryVerify } from "../../deploymentHelpers";
import { IJob, IUpgradeConfig, IProposeTxProperties, IVersions, IFileNames } from "../../types";

export const poolLogicJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  _: IFileNames,
  addresses: IProposeTxProperties,
) => {
  const ethers = hre.ethers;
  const upgrades = hre.upgrades;

  if (config.execute) {
    if (versions[config.oldTag].contracts.PoolLogicProxy) {
      console.log("Will upgrade PoolLogic");

      const PoolLogicLib = await ethers.getContractFactory("PoolLogicLib");
      const poolLogicLib = await PoolLogicLib.deploy();
      await poolLogicLib.deployed();
      console.log("PoolLogicLib deployed at:", poolLogicLib.address);
      versions[config.newTag].contracts.PoolLogicLib = poolLogicLib.address;

      await tryVerify(hre, poolLogicLib.address, "contracts/utils/PoolLogicLib.sol:PoolLogicLib", []);

      const oldPooLogicProxy = versions[config.oldTag].contracts.PoolLogicProxy;
      const PoolLogic = await ethers.getContractFactory("PoolLogic", {
        libraries: {
          PoolLogicLib: poolLogicLib.address,
        },
      });
      const poolLogic = await upgrades.prepareUpgrade(oldPooLogicProxy, PoolLogic, {
        unsafeAllow: ["external-library-linking"],
      });
      console.log("poolLogic deployed to: ", poolLogic);
      versions[config.newTag].contracts.PoolLogic = poolLogic;

      await tryVerify(hre, poolLogic, "contracts/PoolLogic.sol:PoolLogic", []);
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
      console.log("Will deploy PoolLogic");

      const PoolLogicLib = await ethers.getContractFactory("PoolLogicLib");
      const poolLogicLib = await PoolLogicLib.deploy();
      await poolLogicLib.deployed();
      console.log("PoolLogicLib deployed at:", poolLogicLib.address);
      versions[config.newTag].contracts.PoolLogicLib = poolLogicLib.address;

      await tryVerify(hre, poolLogicLib.address, "contracts/utils/PoolLogicLib.sol:PoolLogicLib", []);

      const PoolLogic = await ethers.getContractFactory("PoolLogic", {
        libraries: {
          PoolLogicLib: poolLogicLib.address,
        },
      });
      const poolLogicProxy = await upgrades.deployProxy(PoolLogic, [], {
        initializer: false,
        unsafeAllow: ["external-library-linking"],
      });
      await poolLogicProxy.deployed();
      console.log("PoolLogicProxy deployed at ", poolLogicProxy.address);

      const poolLogicImplementationAddress = await getImplementationAddress(ethers.provider, poolLogicProxy.address);

      await tryVerify(hre, poolLogicImplementationAddress, "contracts/PoolLogic.sol:PoolLogic", []);

      versions[config.newTag].contracts.PoolLogicProxy = poolLogicProxy.address;
      versions[config.newTag].contracts.PoolLogic = poolLogicImplementationAddress;
    }
  }
};
