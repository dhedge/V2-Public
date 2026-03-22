import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx, tryVerify } from "../../../deploymentHelpers";
import { IAddresses, IFileNames, IJob, IUpgradeConfig, IVersions } from "../../../types";
import { addOrReplaceGuardInFile } from "../helpers";

export const fluidMerkleDistributorContractGuardJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  filenames: IFileNames,
  addresses: IAddresses,
) => {
  if (config.execute) {
    const ethers = hre.ethers;

    const merkleDistributor = addresses.fluid?.merkleDistributor;

    if (!merkleDistributor) return console.log("FluidMerkleDistributor contract address not found");

    const FluidMerkleDistributorContractGuard = await ethers.getContractFactory("FluidMerkleDistributorContractGuard");
    const fluidMerkleDistributorContractGuard = await FluidMerkleDistributorContractGuard.deploy();
    await fluidMerkleDistributorContractGuard.deployed();
    const fluidMerkleDistributorContractGuardAddress = fluidMerkleDistributorContractGuard.address;
    console.log("FluidMerkleDistributorContractGuard deployed at", fluidMerkleDistributorContractGuardAddress);

    versions[config.newTag].contracts.FluidMerkleDistributorContractGuard = fluidMerkleDistributorContractGuardAddress;

    await tryVerify(
      hre,
      fluidMerkleDistributorContractGuardAddress,
      "contracts/guards/contractGuards/fluid/FluidMerkleDistributorContractGuard.sol:FluidMerkleDistributorContractGuard",
      [],
    );

    const Governance = await hre.artifacts.readArtifact("Governance");

    await proposeTx(
      versions[config.oldTag].contracts.Governance,
      new ethers.utils.Interface(Governance.abi).encodeFunctionData("setContractGuard", [
        merkleDistributor,
        fluidMerkleDistributorContractGuardAddress,
      ]),
      "setContractGuard for FluidMerkleDistributorContractGuard",
      config,
      addresses,
    );

    const deployedGuard = {
      contractAddress: merkleDistributor,
      guardName: "FluidMerkleDistributorContractGuard",
      guardAddress: fluidMerkleDistributorContractGuardAddress,
      description: "Fluid MerkleDistributor ContractGuard",
    };

    await addOrReplaceGuardInFile(filenames.contractGuardsFileName, deployedGuard, "contractAddress");
  }
};
