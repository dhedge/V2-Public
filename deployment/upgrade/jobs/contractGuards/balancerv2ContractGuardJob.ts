import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx, tryVerify } from "../../../deploymentHelpers";
import { addOrReplaceGuardInFile } from "../helpers";
import { IJob, IAddresses, IUpgradeConfig, IVersions, IFileNames } from "../../../types";

export const balancerv2ContractGuard: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  filenames: IFileNames,
  addresses: IAddresses,
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

    const balancerV2Guard = await BalancerV2Guard.deploy();
    await balancerV2Guard.deployed();
    console.log("BalancerV2Guard deployed at", balancerV2Guard.address);
    versions[config.newTag].contracts.BalancerV2Guard = balancerV2Guard.address;

    await tryVerify(
      hre,
      balancerV2Guard.address,
      "contracts/guards/contractGuards/BalancerV2Guard.sol:BalancerV2Guard",
      [],
    );

    const setContractGuardABI = governanceABI.encodeFunctionData("setContractGuard", [
      addresses.balancerV2VaultAddress,
      balancerV2Guard.address,
    ]);
    await proposeTx(
      versions[config.oldTag].contracts.Governance,
      setContractGuardABI,
      "setContractGuard for balancerV2Vault",
      config,
      addresses,
    );
    const deployedGuard = {
      contractAddress: addresses.balancerV2VaultAddress,
      guardName: "BalancerV2Guard",
      guardAddress: balancerV2Guard.address,
      description: "Balancer V2 Guard",
    };
    await addOrReplaceGuardInFile(filenames.contractGuardsFileName, deployedGuard, "contractAddress");
  }
};
