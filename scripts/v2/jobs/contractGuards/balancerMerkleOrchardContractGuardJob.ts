import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx, tryVerify } from "../../../Helpers";
import { addOrReplaceGuardInFile } from "../helpers";
import { IJob, IUpgradeConfig } from "../../types";

export const balancerMerkleOrchardContractGuardJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  // TODO: This should be types and optimally should not be mutated
  versions: any,
  filenames: { contractGuardsFileName: string },
  addresses: { protocolDaoAddress: string; balancerMerkleOrchardAddress?: string },
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

    let setContractGuardABI = governanceABI.encodeFunctionData("setContractGuard", [
      addresses.balancerMerkleOrchardAddress,
      balancerMerkleOrchardGuard.address,
    ]);
    await proposeTx(
      versions[config.oldTag].contracts.Governance,
      setContractGuardABI,
      "setContractGuard for balancerMerkleOrchard",
      config.execute,
      config.restartnonce,
    );
    const deployedGuard = {
      ContractAddress: addresses.balancerMerkleOrchardAddress,
      GuardName: "BalancerMerkleOrchardGuard",
      GuardAddress: balancerMerkleOrchardGuard.address,
      Description: "Balancer Merkle Orchard Guard",
    };
    await addOrReplaceGuardInFile(filenames.contractGuardsFileName, deployedGuard, "ContractAddress");
  }
};
