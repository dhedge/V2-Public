import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx, tryVerify } from "../../../deploymentHelpers";
import { addOrReplaceGuardInFile } from "../helpers";
import { IAddresses, IJob, IUpgradeConfig, IVersions } from "../../../types";

export const arrakisV1RouterStakingContractGuardJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  filenames: { contractGuardsFileName: string },
  addresses: IAddresses,
) => {
  if (!addresses.arrakisV1?.arrakisV1RouterStakingAddress) {
    console.warn("arrakisV1RouterStakingGuardAddresses not configured for arrakisV1RouterStakingGuard: skipping.");
    return;
  }

  const ethers = hre.ethers;
  const Governance = await hre.artifacts.readArtifact("Governance");
  const governanceABI = new ethers.utils.Interface(Governance.abi);

  console.log("Will deploy arrakisv1routerstakingguard");
  if (config.execute) {
    const ContractGuard = await ethers.getContractFactory("ArrakisV1RouterStakingGuard");
    const contractGuard = await ContractGuard.deploy();
    await contractGuard.deployed();
    console.log("contract guard deployed at", contractGuard.address);
    versions[config.newTag].contracts.ArrakisV1RouterStakingGuard = contractGuard.address;

    await tryVerify(
      hre,
      contractGuard.address,
      "contracts/guards/contractGuards/ArrakisV1RouterStakingGuard.sol:ArrakisV1RouterStakingGuard",
      [],
    );

    const setContractGuardABI = governanceABI.encodeFunctionData("setContractGuard", [
      addresses.arrakisV1.arrakisV1RouterStakingAddress,
      contractGuard.address,
    ]);

    await proposeTx(
      versions[config.oldTag].contracts.Governance,
      setContractGuardABI,
      "setContractGuard for ArrakisV1RouterStakingGuard",
      config,
      addresses,
    );

    const deployedGuard = {
      contractAddress: addresses.arrakisV1.arrakisV1RouterStakingAddress,
      guardName: "ArrakisV1RouterStakingGuard",
      guardAddress: contractGuard.address,
      description: "Arrakis V1 Router Staking Guard",
    };
    await addOrReplaceGuardInFile(filenames.contractGuardsFileName, deployedGuard, "contractAddress");
  }
};
