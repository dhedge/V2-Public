import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx, tryVerify } from "../../../deploymentHelpers";
import { addOrReplaceGuardInFile } from "../helpers";
import { IJob, IProposeTxProperties, IUpgradeConfig, IVersions } from "../../../types";

export const oneInchV4ContractGuardJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  // TODO: This optimally should not be mutated
  versions: IVersions,
  filenames: { contractGuardsFileName: string },
  addresses: { oneInchV4RouterAddress?: string } & IProposeTxProperties,
) => {
  if (!addresses.oneInchV4RouterAddress) {
    console.warn("oneInchV4RouterAddress not configured for oneInchV4ContractGuard: skipping.");
    return;
  }

  const ethers = hre.ethers;
  const Governance = await hre.artifacts.readArtifact("Governance");
  const governanceABI = new ethers.utils.Interface(Governance.abi);

  console.log("Will deploy oneinchv4guard");
  if (config.execute) {
    const OneInchV4Guard = await ethers.getContractFactory("OneInchV4Guard");
    const slippageaccumulatorAddress = versions[config.oldTag].contracts.SlippageAccumulator;
    if (!slippageaccumulatorAddress) {
      console.warn("SlippageAccumulator could not be found: skipping.");
      return;
    }
    const args: [string] = [slippageaccumulatorAddress];
    const oneInchV4Guard = await OneInchV4Guard.deploy(...args);
    await oneInchV4Guard.deployed();
    console.log("oneInchV4Guard deployed at", oneInchV4Guard.address);
    versions[config.newTag].contracts.OneInchV4Guard = oneInchV4Guard.address;

    await tryVerify(
      hre,
      oneInchV4Guard.address,
      "contracts/guards/contractGuards/OneInchV4Guard.sol:OneInchV4Guard",
      args,
    );

    const setContractGuardABI = governanceABI.encodeFunctionData("setContractGuard", [
      addresses.oneInchV4RouterAddress,
      oneInchV4Guard.address,
    ]);

    await proposeTx(
      versions[config.oldTag].contracts.Governance,
      setContractGuardABI,
      "setContractGuard for oneInchV4Guard",
      config,
      addresses,
    );

    const deployedGuard = {
      contractAddress: addresses.oneInchV4RouterAddress,
      guardName: "OneInchV4Guard",
      guardAddress: oneInchV4Guard.address,
      description: "OneInch V4 Router",
    };
    await addOrReplaceGuardInFile(filenames.contractGuardsFileName, deployedGuard, "contractAddress");
  }
};
