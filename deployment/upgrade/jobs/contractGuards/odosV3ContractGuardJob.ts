import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx, tryVerify } from "../../../deploymentHelpers";
import { addOrReplaceGuardInFile } from "../helpers";
import { IJob, IUpgradeConfig, IVersions, IFileNames, IAddresses, Address } from "../../../types";

export const odosV3ContractGuardJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  filenames: IFileNames,
  addresses: IAddresses,
) => {
  if (!addresses.odosV3RouterAddress) {
    return console.warn("odosV3RouterAddress not configured for odosV3ContractGuardJob: skipping.");
  }

  const ethers = hre.ethers;
  const Governance = await hre.artifacts.readArtifact("Governance");

  console.log("Will deploy OdosV3ContractGuard");

  if (config.execute) {
    const slippageAccumulatorAddress = versions[config.oldTag].contracts.SlippageAccumulator;

    if (!slippageAccumulatorAddress) {
      return console.warn("SlippageAccumulator could not be found: skipping.");
    }

    const OdosV3ContractGuard = await ethers.getContractFactory("OdosV3ContractGuard");
    const args: [Address] = [slippageAccumulatorAddress];
    const odosV3ContractGuard = await OdosV3ContractGuard.deploy(...args);
    await odosV3ContractGuard.deployed();
    const odosV3ContractGuardAddress = odosV3ContractGuard.address;

    console.log("OdosV3ContractGuard deployed at", odosV3ContractGuardAddress);

    versions[config.newTag].contracts.OdosV3ContractGuard = odosV3ContractGuardAddress;

    await tryVerify(
      hre,
      odosV3ContractGuardAddress,
      "contracts/guards/contractGuards/odos/OdosV3ContractGuard.sol:OdosV3ContractGuard",
      args,
    );

    const setContractGuardABI = new ethers.utils.Interface(Governance.abi).encodeFunctionData("setContractGuard", [
      addresses.odosV3RouterAddress,
      odosV3ContractGuardAddress,
    ]);

    await proposeTx(
      versions[config.oldTag].contracts.Governance,
      setContractGuardABI,
      "setContractGuard for OdosV3ContractGuard",
      config,
      addresses,
    );

    const deployedGuard = {
      contractAddress: addresses.odosV3RouterAddress,
      guardName: "OdosV3ContractGuard",
      guardAddress: odosV3ContractGuardAddress,
      description: "Odos V3 Router",
    };
    await addOrReplaceGuardInFile(filenames.contractGuardsFileName, deployedGuard, "contractAddress");
  }
};
