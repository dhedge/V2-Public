import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx, tryVerify } from "../../../deploymentHelpers";
import { IAddresses, IFileNames, IJob, IUpgradeConfig, IVersions } from "../../../types";
import { addOrReplaceGuardInFile } from "../helpers";

/***
 * Deploys the StargateLpStakingContractGuard
 */
export const stargateLpStakingContractGuardJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  filenames: IFileNames,
  addresses: IAddresses,
) => {
  const ethers = hre.ethers;

  if (!addresses.stargate.staking) {
    console.warn("stargate.router not configured for StargateLpStakingContractGuard: skipping.");
    return;
  }

  console.log("Will deploy Stargate LP staking contract guard");
  if (config.execute) {
    const ContractGuard = await ethers.getContractFactory("StargateLpStakingContractGuard");
    const contractGuard = await ContractGuard.deploy();
    await contractGuard.deployed();
    await contractGuard.deployTransaction.wait(5);
    console.log("contract guard deployed at", contractGuard.address);

    await tryVerify(
      hre,
      contractGuard.address,
      "contracts/guards/contractGuards/StargateLpStakingContractGuard.sol:StargateLpStakingContractGuard",
      [],
    );
    versions[config.newTag].contracts.StargateLpStakingContractGuard = contractGuard.address;

    const Governance = await hre.artifacts.readArtifact("Governance");
    const governanceABI = new ethers.utils.Interface(Governance.abi);
    const setContractGuardABI = governanceABI.encodeFunctionData("setContractGuard", [
      addresses.stargate.staking,
      contractGuard.address,
    ]);

    await proposeTx(
      versions[config.oldTag].contracts.Governance,
      setContractGuardABI,
      "setContractGuard for StargateLpStakingContractGuard",
      config,
      addresses,
    );

    const deployedGuard = {
      contractAddress: addresses.stargate.staking,
      guardName: "StargateLpStakingContractGuard",
      guardAddress: contractGuard.address,
      description: "Stargate Lp Staking Contract Guard",
    };
    await addOrReplaceGuardInFile(filenames.contractGuardsFileName, deployedGuard, "contractAddress");
  }
};
