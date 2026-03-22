import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx, tryVerify } from "../../deploymentHelpers";
import { IJob, IProposeTxProperties, IUpgradeConfig, IVersions, IFileNames } from "../../types";

export const poolLogicAndManagerLogicJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  _: IFileNames,
  addresses: IProposeTxProperties,
) => {
  const ethers = hre.ethers;
  const upgrades = hre.upgrades;

  if (!config.execute) return;

  const oldPoolLogicProxy = versions[config.oldTag].contracts.PoolLogicProxy;
  const oldPoolManagerLogicProxy = versions[config.oldTag].contracts.PoolManagerLogicProxy;

  if (!oldPoolLogicProxy || !oldPoolManagerLogicProxy) {
    throw new Error("Both PoolLogicProxy and PoolManagerLogicProxy must exist for a combined upgrade");
  }

  // --- Deploy PoolLogicLib + PoolLogic ---
  console.log("Deploying PoolLogicLib");
  const PoolLogicLib = await ethers.getContractFactory("PoolLogicLib");
  const poolLogicLib = await PoolLogicLib.deploy();
  await poolLogicLib.deployed();
  console.log("PoolLogicLib deployed at:", poolLogicLib.address);
  versions[config.newTag].contracts.PoolLogicLib = poolLogicLib.address;

  await tryVerify(hre, poolLogicLib.address, "contracts/utils/PoolLogicLib.sol:PoolLogicLib", []);

  console.log("Upgrading PoolLogic");
  const PoolLogic = await ethers.getContractFactory("PoolLogic", {
    libraries: { PoolLogicLib: poolLogicLib.address },
  });
  const poolLogic = await upgrades.prepareUpgrade(oldPoolLogicProxy, PoolLogic, {
    unsafeAllow: ["external-library-linking"],
  });
  console.log("PoolLogic deployed to:", poolLogic);
  versions[config.newTag].contracts.PoolLogic = poolLogic;

  await tryVerify(hre, poolLogic, "contracts/PoolLogic.sol:PoolLogic", []);

  // --- Deploy PoolManagerLogic ---
  console.log("Upgrading PoolManagerLogic");
  const PoolManagerLogic = await ethers.getContractFactory("PoolManagerLogic");
  const poolManagerLogic = await upgrades.prepareUpgrade(oldPoolManagerLogicProxy, PoolManagerLogic);
  console.log("PoolManagerLogic deployed to:", poolManagerLogic);
  versions[config.newTag].contracts.PoolManagerLogic = poolManagerLogic;

  await tryVerify(hre, poolManagerLogic, "contracts/PoolManagerLogic.sol:PoolManagerLogic", []);

  // --- Single setLogic call for both ---
  const PoolFactory = await hre.artifacts.readArtifact("PoolFactory");
  const setLogicABI = new ethers.utils.Interface(PoolFactory.abi).encodeFunctionData("setLogic", [
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

  console.log("PoolLogic and PoolManagerLogic upgraded with a single setLogic call");
};
