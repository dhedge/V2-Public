import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx, tryVerify } from "../../../deploymentHelpers";
import { addOrReplaceGuardInFile } from "../helpers";
import { IJob, IUpgradeConfig, IVersions, IFileNames, IAddresses } from "../../../types";

export const oneInchV6ContractGuardJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  filenames: IFileNames,
  addresses: IAddresses,
) => {
  if (!addresses.oneInchV6RouterAddress) {
    return console.warn("oneInchV6RouterAddress not configured for oneInchV6ContractGuardJob: skipping.");
  }

  const ethers = hre.ethers;
  const Governance = await hre.artifacts.readArtifact("Governance");

  console.log("Will deploy OneInchV6Guard");

  if (config.execute) {
    const slippageAccumulatorAddress = versions[config.oldTag].contracts.SlippageAccumulator;

    if (!slippageAccumulatorAddress) {
      return console.warn("SlippageAccumulator could not be found: skipping.");
    }

    const OneInchV6Guard = await ethers.getContractFactory("OneInchV6Guard");
    const args: [string] = [slippageAccumulatorAddress];
    const oneInchV6Guard = await OneInchV6Guard.deploy(...args);
    await oneInchV6Guard.deployed();
    const oneInchV6GuardAddress = oneInchV6Guard.address;

    console.log("OneInchV6Guard deployed at", oneInchV6GuardAddress);

    versions[config.newTag].contracts.OneInchV6Guard = oneInchV6GuardAddress;

    await tryVerify(
      hre,
      oneInchV6GuardAddress,
      "contracts/guards/contractGuards/OneInchV6Guard.sol:OneInchV6Guard",
      args,
    );

    const setContractGuardABI = new ethers.utils.Interface(Governance.abi).encodeFunctionData("setContractGuard", [
      addresses.oneInchV6RouterAddress,
      oneInchV6GuardAddress,
    ]);

    await proposeTx(
      versions[config.oldTag].contracts.Governance,
      setContractGuardABI,
      "setContractGuard for OneInchV6Guard",
      config,
      addresses,
    );

    const deployedGuard = {
      contractAddress: addresses.oneInchV6RouterAddress,
      guardName: "OneInchV6Guard",
      guardAddress: oneInchV6GuardAddress,
      description: "OneInch V6 Router",
    };
    await addOrReplaceGuardInFile(filenames.contractGuardsFileName, deployedGuard, "contractAddress");
  }
};
