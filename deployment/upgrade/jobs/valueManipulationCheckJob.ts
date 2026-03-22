import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx, tryVerify } from "../../deploymentHelpers";
import { IJob, IProposeTxProperties, IUpgradeConfig, IVersions, IFileNames } from "../../types";

export const valueManipulationCheckJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  _: IFileNames,
  addresses: IProposeTxProperties,
) => {
  const ethers = hre.ethers;

  if (config.execute) {
    console.log("Will deploy ValueManipulationCheck");

    if (!versions[config.oldTag].contracts.PoolFactoryProxy) {
      return console.log("No pool factory proxy address");
    }

    const ValueManipulationCheckFactory = await ethers.getContractFactory("ValueManipulationCheck");
    const valueManipulationCheck = await ValueManipulationCheckFactory.deploy();
    await valueManipulationCheck.deployed();
    console.log("ValueManipulationCheck deployed at ", valueManipulationCheck.address);

    await tryVerify(
      hre,
      valueManipulationCheck.address,
      "contracts/utils/ValueManipulationCheck.sol:ValueManipulationCheck",
      [],
    );

    versions[config.newTag].contracts.ValueManipulationCheck = valueManipulationCheck.address;

    // Propose transaction to set the ValueManipulationCheck on PoolFactory
    const PoolFactory = await hre.artifacts.readArtifact("PoolFactory");
    const poolFactoryInterface = new ethers.utils.Interface(PoolFactory.abi);
    const setValueManipulationCheckABI = poolFactoryInterface.encodeFunctionData("setValueManipulationCheck", [
      valueManipulationCheck.address,
    ]);

    await proposeTx(
      versions[config.oldTag].contracts.PoolFactoryProxy,
      setValueManipulationCheckABI,
      "Set ValueManipulationCheck on PoolFactory",
      config,
      addresses,
    );

    console.log("ValueManipulationCheck deployment complete.");
    console.log("NOTE: The PoolFactory.setValueManipulationCheck() transaction has been proposed.");
  }
};
