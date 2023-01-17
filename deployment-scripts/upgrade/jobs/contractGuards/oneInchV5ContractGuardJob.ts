import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx, tryVerify } from "../../../Helpers";
import { addOrReplaceGuardInFile } from "../helpers";
import { IJob, IProposeTxProperties, IUpgradeConfig, IVersions } from "../../../types";

export const oneInchV5ContractGuardJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  // TODO: This optimally should not be mutated
  versions: IVersions,
  filenames: { contractGuardsFileName: string },
  addresses: { oneInchV5RouterAddress?: string } & IProposeTxProperties,
) => {
  if (!addresses.oneInchV5RouterAddress) {
    console.warn("oneInchV5RouterAddress not configured for oneInchV5ContractGuard: skipping.");
    return;
  }

  const ethers = hre.ethers;
  const Governance = await hre.artifacts.readArtifact("Governance");
  const governanceABI = new ethers.utils.Interface(Governance.abi);

  console.log("Will deploy oneinchv5guard");
  if (config.execute) {
    const OneInchV5Guard = await ethers.getContractFactory("OneInchV5Guard");
    const oneInchV5Guard = await OneInchV5Guard.deploy(10, 100); // set slippage 10%
    await oneInchV5Guard.deployed();
    console.log("oneInchV5Guard deployed at", oneInchV5Guard.address);
    versions[config.newTag].contracts.OneInchV5Guard = oneInchV5Guard.address;

    await tryVerify(
      hre,
      oneInchV5Guard.address,
      "contracts/guards/contractGuards/OneInchV5Guard.sol:OneInchV5Guard",
      [10, 100],
    );

    const setContractGuardABI = governanceABI.encodeFunctionData("setContractGuard", [
      addresses.oneInchV5RouterAddress,
      oneInchV5Guard.address,
    ]);

    await proposeTx(
      versions[config.oldTag].contracts.Governance,
      setContractGuardABI,
      "setContractGuard for oneInchV5Guard",
      config,
      addresses,
    );

    const deployedGuard = {
      contractAddress: addresses.oneInchV5RouterAddress,
      guardName: "OneInchV5Guard",
      guardAddress: oneInchV5Guard.address,
      description: "OneInch V5 Router",
    };
    await addOrReplaceGuardInFile(filenames.contractGuardsFileName, deployedGuard, "contractAddress");
  }
};
