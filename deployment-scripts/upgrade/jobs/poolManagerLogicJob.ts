import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx, tryVerify } from "../../Helpers";
import { IJob, IProposeTxProperties, IUpgradeConfig, IVersions } from "../../types";

export const poolManagerLogicJob: IJob<void> = async (
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

  console.log("Will upgrade poolmanagerlogic");
  if (config.execute) {
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
  }
};
