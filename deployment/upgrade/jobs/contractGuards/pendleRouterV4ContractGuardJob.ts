import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx, tryVerify } from "../../../deploymentHelpers";
import { addOrReplaceGuardInFile } from "../helpers";
import { IJob, IUpgradeConfig, IVersions, IFileNames, IAddresses, Address } from "../../../types";

export const pendleRouterV4ContractGuardJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  filenames: IFileNames,
  addresses: IAddresses,
) => {
  const pendleRouterV4Address = addresses.pendle?.pendleRouterV4;

  if (!pendleRouterV4Address) {
    return console.warn("pendleRouterV4Address not configured for pendleRouterV4ContractGuardJob: skipping.");
  }

  const ethers = hre.ethers;

  console.log("Will deploy PendleRouterV4ContractGuard");

  if (config.execute) {
    const slippageAccumulatorAddress = versions[config.oldTag].contracts.SlippageAccumulator;

    if (!slippageAccumulatorAddress) {
      return console.warn("SlippageAccumulator could not be found: skipping.");
    }

    const PendleRouterV4ContractGuard = await ethers.getContractFactory("PendleRouterV4ContractGuard");
    const args: [Address] = [slippageAccumulatorAddress];
    const pendleRouterV4ContractGuard = await PendleRouterV4ContractGuard.deploy(...args);
    await pendleRouterV4ContractGuard.deployed();
    const pendleRouterV4ContractGuardAddress = pendleRouterV4ContractGuard.address;

    console.log("PendleRouterV4ContractGuard deployed at", pendleRouterV4ContractGuardAddress);
    versions[config.newTag].contracts.PendleRouterV4ContractGuard = pendleRouterV4ContractGuardAddress;

    await tryVerify(
      hre,
      pendleRouterV4ContractGuardAddress,
      "contracts/guards/contractGuards/pendle/PendleRouterV4ContractGuard.sol:PendleRouterV4ContractGuard",
      args,
    );

    const Governance = await hre.artifacts.readArtifact("Governance");
    const setContractGuardABI = new ethers.utils.Interface(Governance.abi).encodeFunctionData("setContractGuard", [
      pendleRouterV4Address,
      pendleRouterV4ContractGuardAddress,
    ]);

    await proposeTx(
      versions[config.oldTag].contracts.Governance,
      setContractGuardABI,
      "setContractGuard for PendleRouterV4ContractGuard",
      config,
      addresses,
    );

    const deployedGuard = {
      contractAddress: pendleRouterV4Address,
      guardName: "PendleRouterV4ContractGuard",
      guardAddress: pendleRouterV4ContractGuardAddress,
      description: "Pendle Router V4",
    };

    await addOrReplaceGuardInFile(filenames.contractGuardsFileName, deployedGuard, "contractAddress");
  }
};
