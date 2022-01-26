import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx, tryVerify } from "../../Helpers";
import { IJob, IUpgradeConfig } from "./types";

export const poolManagerLogicJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  // TODO: This should be types and optimally should not be mutated
  versions: any,
  filenames: {},
  addresses: {},
) => {
  const ethers = hre.ethers;
  const upgrades = hre.upgrades;

  console.log("Will upgrade poolmanagerlogic");
  if (config.execute) {
    let oldPooManagerLogicProxy = versions[config.oldTag].contracts.PoolManagerLogicProxy;
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
      config.execute,
      config.restartnonce,
    );
  }
};
