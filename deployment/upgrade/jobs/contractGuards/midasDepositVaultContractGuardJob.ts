import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx, tryVerify } from "../../../deploymentHelpers";
import { addOrReplaceGuardInFile } from "../helpers";
import { IJob, IUpgradeConfig, IVersions, IFileNames, IAddresses } from "../../../types";

// The deposit guard is not whitelist-gated: minting requires the mToken to be a supported asset,
// which is only possible for whitelisted pools (MidasMTokenAssetGuard.addAssetCheck), so an
// un-whitelisted pool's depositInstant reverts on the unsupported-asset check anyway.
export const midasDepositVaultContractGuardJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  filenames: IFileNames,
  addresses: IAddresses,
) => {
  if (!addresses.midas) {
    return console.warn("midas config not set: skipping midasDepositVaultContractGuardJob.");
  }

  const { depositVault } = addresses.midas;

  const slippageAccumulatorAddress = versions[config.oldTag].contracts.SlippageAccumulator;
  if (!slippageAccumulatorAddress) return console.warn("SlippageAccumulator not found: skipping.");

  console.log("Will deploy MidasDepositVaultContractGuard");

  if (config.execute) {
    const ethers = hre.ethers;
    const Governance = await hre.artifacts.readArtifact("Governance");

    const MidasDepositVaultContractGuard = await ethers.getContractFactory("MidasDepositVaultContractGuard");
    const args = [slippageAccumulatorAddress] as const;
    const midasDepositVaultContractGuard = await MidasDepositVaultContractGuard.deploy(...args);
    await midasDepositVaultContractGuard.deployed();
    const guardAddress = midasDepositVaultContractGuard.address;

    console.log("MidasDepositVaultContractGuard deployed at", guardAddress);
    versions[config.newTag].contracts.MidasDepositVaultContractGuard = guardAddress;

    await tryVerify(
      hre,
      guardAddress,
      "contracts/guards/contractGuards/midas/MidasDepositVaultContractGuard.sol:MidasDepositVaultContractGuard",
      [...args],
    );

    const setContractGuardABI = new ethers.utils.Interface(Governance.abi).encodeFunctionData("setContractGuard", [
      depositVault,
      guardAddress,
    ]);
    await proposeTx(
      versions[config.oldTag].contracts.Governance,
      setContractGuardABI,
      "setContractGuard for MidasDepositVaultContractGuard",
      config,
      addresses,
    );

    const deployedGuard = {
      contractAddress: depositVault,
      guardName: "MidasDepositVaultContractGuard",
      guardAddress,
      description: "Midas Deposit Vault",
    };
    await addOrReplaceGuardInFile(filenames.contractGuardsFileName, deployedGuard, "contractAddress");
  }
};
