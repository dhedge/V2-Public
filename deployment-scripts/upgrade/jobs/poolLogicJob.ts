import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx, tryVerify } from "../../Helpers";
import { IJob, IUpgradeConfig, IProposeTxProperties, IVersions } from "../../types";

export const poolLogicJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  // TODO: This should be types and optimally should not be mutated
  versions: IVersions,
  _: {},
  addresses: IProposeTxProperties,
) => {
  const ethers = hre.ethers;
  const upgrades = hre.upgrades;

  console.log("Will upgrade poollogic");
  if (config.execute) {
    let oldPooLogicProxy = versions[config.oldTag].contracts.PoolLogicProxy;
    const PoolLogic = await ethers.getContractFactory("PoolLogic");
    const poolLogic = await upgrades.prepareUpgrade(oldPooLogicProxy, PoolLogic);
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
  }
};
