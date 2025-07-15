import { HardhatRuntimeEnvironment } from "hardhat/types";

import { proposeTx, tryVerify } from "../../../deploymentHelpers";
import { IDeployedContractGuard, IJob, IUpgradeConfig, IVersions, IFileNames, IAddresses } from "../../../types";
import { addOrReplaceGuardInFile } from "../helpers";

export const skyPSM3ContractGuardJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  filenames: IFileNames,
  addresses: IAddresses,
) => {
  const psm3 = addresses.sky?.psm3;

  if (!psm3) return console.warn("PSM3 could not be found: skipping.");

  const slippageaccumulatorAddress = versions[config.newTag].contracts.SlippageAccumulator;

  if (!slippageaccumulatorAddress) return console.warn("SlippageAccumulator could not be found: skipping.");

  const ethers = hre.ethers;

  console.log("Will deploy SkyPSM3ContractGuard");

  if (config.execute) {
    const SkyPSM3ContractGuard = await ethers.getContractFactory("SkyPSM3ContractGuard");
    const args: Parameters<typeof SkyPSM3ContractGuard.deploy> = [slippageaccumulatorAddress];
    const skyPSM3ContractGuard = await SkyPSM3ContractGuard.deploy(...args);
    await skyPSM3ContractGuard.deployed();
    const skyPSM3ContractGuardAddress = skyPSM3ContractGuard.address;

    console.log("SkyPSM3ContractGuard deployed at: ", skyPSM3ContractGuardAddress);

    versions[config.newTag].contracts.SkyPSM3ContractGuard = skyPSM3ContractGuardAddress;

    await tryVerify(
      hre,
      skyPSM3ContractGuardAddress,
      "contracts/guards/contractGuards/SkyPSM3ContractGuard.sol:SkyPSM3ContractGuard",
      args,
    );

    const Governance = await hre.artifacts.readArtifact("Governance");
    await proposeTx(
      versions[config.oldTag].contracts.Governance,
      new ethers.utils.Interface(Governance.abi).encodeFunctionData("setContractGuard", [
        psm3,
        skyPSM3ContractGuardAddress,
      ]),
      "setContractGuard for Sky PSM3",
      config,
      addresses,
    );

    const deployedGuard: IDeployedContractGuard = {
      contractAddress: psm3,
      guardName: "SkyPSM3ContractGuard",
      guardAddress: skyPSM3ContractGuardAddress,
      description: "Sky PSM3 - allows buying USDS",
    };
    await addOrReplaceGuardInFile(filenames.contractGuardsFileName, deployedGuard, "contractAddress");
  }
};
