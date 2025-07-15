import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx, tryVerify } from "../../../deploymentHelpers";
import { addOrReplaceGuardInFile } from "../helpers";
import { IJob, IUpgradeConfig, IVersions, IFileNames, IAddresses, Address } from "../../../types";

export const odosV2ContractGuardJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  filenames: IFileNames,
  addresses: IAddresses,
) => {
  if (!addresses.odosV2RouterAddress) {
    return console.warn("odosV2RouterAddress not configured for odosV2ContractGuardJob: skipping.");
  }

  const ethers = hre.ethers;
  const Governance = await hre.artifacts.readArtifact("Governance");

  console.log("Will deploy OdosV2ContractGuard");

  if (config.execute) {
    const slippageAccumulatorAddress = versions[config.oldTag].contracts.SlippageAccumulator;

    if (!slippageAccumulatorAddress) {
      return console.warn("SlippageAccumulator could not be found: skipping.");
    }

    const OdosV2ContractGuard = await ethers.getContractFactory("OdosV2ContractGuard");
    const args: [Address] = [slippageAccumulatorAddress];
    const odosV2ContractGuard = await OdosV2ContractGuard.deploy(...args);
    await odosV2ContractGuard.deployed();
    const odosV2ContractGuardAddress = odosV2ContractGuard.address;

    console.log("OdosV2ContractGuard deployed at", odosV2ContractGuardAddress);

    versions[config.newTag].contracts.OdosV2ContractGuard = odosV2ContractGuardAddress;

    await tryVerify(
      hre,
      odosV2ContractGuardAddress,
      "contracts/guards/contractGuards/odos/OdosV2ContractGuard.sol:OdosV2ContractGuard",
      args,
    );

    const setContractGuardABI = new ethers.utils.Interface(Governance.abi).encodeFunctionData("setContractGuard", [
      addresses.odosV2RouterAddress,
      odosV2ContractGuardAddress,
    ]);

    await proposeTx(
      versions[config.oldTag].contracts.Governance,
      setContractGuardABI,
      "setContractGuard for OdosV2ContractGuard",
      config,
      addresses,
    );

    const deployedGuard = {
      contractAddress: addresses.odosV2RouterAddress,
      guardName: "OdosV2ContractGuard",
      guardAddress: odosV2ContractGuardAddress,
      description: "Odos V2 Router",
    };
    await addOrReplaceGuardInFile(filenames.contractGuardsFileName, deployedGuard, "contractAddress");
  }
};
