import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx, tryVerify } from "../../../deploymentHelpers";
import { IAddresses, IFileNames, IJob, IUpgradeConfig, IVersions } from "../../../types";
import { addOrReplaceGuardInFile } from "../helpers";

/***
 * Deploys the StargateRouterContractGuard
 */
export const stargateRouterContractGuardJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  filenames: IFileNames,
  addresses: IAddresses,
) => {
  const ethers = hre.ethers;

  if (!addresses.stargate.router) {
    console.warn("stargate.router not configured for StargateRouterContractGuard: skipping.");
    return;
  }

  console.log("Will deploy Stargate router contract guard");
  if (config.execute) {
    const ContractGuard = await ethers.getContractFactory("StargateRouterContractGuard");
    const contractGuard = await ContractGuard.deploy();
    await contractGuard.deployed();
    await contractGuard.deployTransaction.wait(5);
    console.log("contract guard deployed at", contractGuard.address);

    await tryVerify(
      hre,
      contractGuard.address,
      "contracts/guards/contractGuards/StargateRouterContractGuard.sol:StargateRouterContractGuard",
      [],
    );
    versions[config.newTag].contracts.StargateRouterContractGuard = contractGuard.address;

    const Governance = await hre.artifacts.readArtifact("Governance");
    const governanceABI = new ethers.utils.Interface(Governance.abi);
    const setContractGuardABI = governanceABI.encodeFunctionData("setContractGuard", [
      addresses.stargate.router,
      contractGuard.address,
    ]);

    await proposeTx(
      versions[config.oldTag].contracts.Governance,
      setContractGuardABI,
      "setContractGuard for StargateRouterContractGuard",
      config,
      addresses,
    );

    const deployedGuard = {
      contractAddress: addresses.stargate.router,
      guardName: "StargateRouterContractGuard",
      guardAddress: contractGuard.address,
      description: "Stargate Router Contract Guard",
    };
    await addOrReplaceGuardInFile(filenames.contractGuardsFileName, deployedGuard, "contractAddress");
  }
};
