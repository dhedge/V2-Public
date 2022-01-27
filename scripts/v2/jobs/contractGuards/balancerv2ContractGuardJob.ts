import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx, tryVerify } from "../../../Helpers";
import { addOrReplaceGuardInFile } from "../helpers";
import { IJob, IUpgradeConfig } from "../../types";

export const balancerv2ContractGuard: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  // TODO: This should be types and optimally should not be mutated
  versions: any,
  filenames: { contractGuardsFileName: string },
  addresses: { protocolDaoAddress: string; balancerV2VaultAddress?: string },
) => {
  if (!addresses.balancerV2VaultAddress) {
    console.warn("balancerV2VaultAddress not configured for balancerv2ContractGuard: skipping.");
    return;
  }

  const ethers = hre.ethers;
  const Governance = await hre.artifacts.readArtifact("Governance");
  const governanceABI = new ethers.utils.Interface(Governance.abi);

  console.log("Will deploy balancerv2guard");
  if (config.execute) {
    const BalancerV2Guard = await ethers.getContractFactory("BalancerV2Guard");
    const balancerV2Guard = await BalancerV2Guard.deploy(10, 100); // set slippage 10%
    await balancerV2Guard.deployed();
    console.log("BalancerV2Guard deployed at", balancerV2Guard.address);
    versions[config.newTag].contracts.BalancerV2Guard = balancerV2Guard.address;

    await tryVerify(
      hre,
      balancerV2Guard.address,
      "contracts/guards/contractGuards/BalancerV2Guard.sol:BalancerV2Guard",
      [10, 100],
    );

    await balancerV2Guard.transferOwnership(addresses.protocolDaoAddress);
    let setContractGuardABI = governanceABI.encodeFunctionData("setContractGuard", [
      addresses.balancerV2VaultAddress,
      balancerV2Guard.address,
    ]);
    await proposeTx(
      versions[config.oldTag].contracts.Governance,
      setContractGuardABI,
      "setContractGuard for balancerV2Vault",
      config.execute,
      config.restartnonce,
    );
    const deployedGuard = {
      ContractAddress: addresses.balancerV2VaultAddress,
      GuardName: "BalancerV2Guard",
      GuardAddress: balancerV2Guard.address,
      Description: "Balancer V2 Guard",
    };
    await addOrReplaceGuardInFile(filenames.contractGuardsFileName, deployedGuard, "ContractAddress");
  }
};
