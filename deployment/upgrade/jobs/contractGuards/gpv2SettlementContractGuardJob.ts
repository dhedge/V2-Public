import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx, tryVerify } from "../../../deploymentHelpers";
import { addOrReplaceGuardInFile } from "../helpers";
import { IJob, IUpgradeConfig, IVersions, IFileNames, IAddresses, Address } from "../../../types";

export const gpv2SettlementContractGuardJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  filenames: IFileNames,
  addresses: IAddresses,
) => {
  const gpv2SettlementAddress = addresses.typedStructuredDataValidator?.cowSwapOrder?.gpv2Settlement;

  if (!gpv2SettlementAddress) {
    return console.warn("gpv2Settlement not configured for gpv2SettlementContractGuardJob: skipping.");
  }

  const ethers = hre.ethers;

  console.log("Will deploy GPv2SettlementContractGuard");

  if (config.execute) {
    const poolFactoryAddress = versions[config.oldTag].contracts.PoolFactoryProxy;

    if (!poolFactoryAddress) {
      return console.warn("PoolFactoryProxy not found: skipping.");
    }

    const GPv2SettlementContractGuard = await ethers.getContractFactory("GPv2SettlementContractGuard");
    const args: [Address] = [poolFactoryAddress];
    const gpv2SettlementContractGuard = await GPv2SettlementContractGuard.deploy(...args);
    await gpv2SettlementContractGuard.deployed();
    const gpv2SettlementContractGuardAddress = gpv2SettlementContractGuard.address;

    console.log("GPv2SettlementContractGuard deployed at", gpv2SettlementContractGuardAddress);
    versions[config.newTag].contracts.GPv2SettlementContractGuard = gpv2SettlementContractGuardAddress;

    await tryVerify(
      hre,
      gpv2SettlementContractGuardAddress,
      "contracts/guards/contractGuards/cowSwap/GPv2SettlementContractGuard.sol:GPv2SettlementContractGuard",
      args,
    );

    const Governance = await hre.artifacts.readArtifact("Governance");
    const setContractGuardABI = new ethers.utils.Interface(Governance.abi).encodeFunctionData("setContractGuard", [
      gpv2SettlementAddress,
      gpv2SettlementContractGuardAddress,
    ]);

    await proposeTx(
      versions[config.oldTag].contracts.Governance,
      setContractGuardABI,
      "setContractGuard for GPv2SettlementContractGuard",
      config,
      addresses,
    );

    const deployedGuard = {
      contractAddress: gpv2SettlementAddress,
      guardName: "GPv2SettlementContractGuard",
      guardAddress: gpv2SettlementContractGuardAddress,
      description: "CoWSwap GPv2 Settlement",
    };

    await addOrReplaceGuardInFile(filenames.contractGuardsFileName, deployedGuard, "contractAddress");
  }
};
