import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx, tryVerify } from "../../../deploymentHelpers";
import { addOrReplaceGuardInFile } from "../helpers";
import { IJob, IProposeTxProperties, IUpgradeConfig, IVersions } from "../../../types";

export const balancerMerkleOrchardContractGuardJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  // TODO: This optimally should not be mutated
  versions: IVersions,
  filenames: { contractGuardsFileName: string },
  addresses: { balancerMerkleOrchardAddress?: string } & IProposeTxProperties,
) => {
  if (!addresses.balancerMerkleOrchardAddress) {
    console.warn("balancerMerkleOrchardAddress not configured for balancerv2ContractGuard: skipping.");
    return;
  }

  const ethers = hre.ethers;
  const Governance = await hre.artifacts.readArtifact("Governance");
  const governanceABI = new ethers.utils.Interface(Governance.abi);

  console.log("Will deploy balancermerkleorchardguard");
  if (config.execute) {
    const BalancerMerkleOrchardGuard = await ethers.getContractFactory("BalancerMerkleOrchardGuard");
    const balancerMerkleOrchardGuard = await BalancerMerkleOrchardGuard.deploy();
    await balancerMerkleOrchardGuard.deployed();
    console.log("BalancerMerkleOrchardGuard deployed at", balancerMerkleOrchardGuard.address);
    versions[config.newTag].contracts.BalancerMerkleOrchardGuard = balancerMerkleOrchardGuard.address;

    await tryVerify(
      hre,
      balancerMerkleOrchardGuard.address,
      "contracts/guards/contractGuards/BalancerMerkleOrchardGuard.sol:BalancerMerkleOrchardGuard",
      [],
    );

    const setContractGuardABI = governanceABI.encodeFunctionData("setContractGuard", [
      addresses.balancerMerkleOrchardAddress,
      balancerMerkleOrchardGuard.address,
    ]);
    await proposeTx(
      versions[config.oldTag].contracts.Governance,
      setContractGuardABI,
      "setContractGuard for balancerMerkleOrchard",
      config,
      addresses,
    );
    const deployedGuard = {
      contractAddress: addresses.balancerMerkleOrchardAddress,
      guardName: "BalancerMerkleOrchardGuard",
      guardAddress: balancerMerkleOrchardGuard.address,
      description: "Balancer Merkle Orchard Guard",
    };
    await addOrReplaceGuardInFile(filenames.contractGuardsFileName, deployedGuard, "contractAddress");
  }
};
