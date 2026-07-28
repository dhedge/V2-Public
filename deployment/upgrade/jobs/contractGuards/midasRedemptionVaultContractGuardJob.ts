import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx, tryVerify } from "../../../deploymentHelpers";
import { addOrReplaceGuardInFile } from "../helpers";
import { IJob, IUpgradeConfig, IVersions, IFileNames, IAddresses } from "../../../types";

// Deploy order within the Midas integration: this job runs FIRST — it is the integration's single
// owned contract (async request tracking + the pool whitelist), and the deposit vault guard and both
// Midas asset guards resolve the whitelist through the contract guard registered here.
//
// REDEPLOYMENT: the guard seeds its whitelist from deploymentData `midas.whitelistedPools` only, and
// `pendingRequestIds` lives in its storage. Replacing it while pools are whitelisted on-chain (via
// setPoolsWhitelist) or hold Pending requests would drop that state. Settle/reject all requests and
// reconcile the whitelist config before redeploying.
export const midasRedemptionVaultContractGuardJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  filenames: IFileNames,
  addresses: IAddresses,
) => {
  if (!addresses.midas) {
    return console.warn("midas config not set: skipping midasRedemptionVaultContractGuardJob.");
  }

  const { redemptionVault, whitelistedPools } = addresses.midas;

  const slippageAccumulatorAddress = versions[config.oldTag].contracts.SlippageAccumulator;
  if (!slippageAccumulatorAddress) return console.warn("SlippageAccumulator not found: skipping.");

  console.log("Will deploy MidasRedemptionVaultContractGuard");

  if (config.execute) {
    const ethers = hre.ethers;
    const Governance = await hre.artifacts.readArtifact("Governance");

    const MidasRedemptionVaultContractGuard = await ethers.getContractFactory("MidasRedemptionVaultContractGuard");
    const args = [slippageAccumulatorAddress, whitelistedPools] as const;
    const midasRedemptionVaultContractGuard = await MidasRedemptionVaultContractGuard.deploy(...args);
    await midasRedemptionVaultContractGuard.deployed();
    const guardAddress = midasRedemptionVaultContractGuard.address;

    console.log("MidasRedemptionVaultContractGuard deployed at", guardAddress);
    versions[config.newTag].contracts.MidasRedemptionVaultContractGuard = guardAddress;

    // Hand the whitelist owner role to the protocol DAO (deployer owns it after construction).
    await midasRedemptionVaultContractGuard.transferOwnership(addresses.protocolDaoAddress);

    await tryVerify(
      hre,
      guardAddress,
      "contracts/guards/contractGuards/midas/MidasRedemptionVaultContractGuard.sol:MidasRedemptionVaultContractGuard",
      [...args],
    );

    const setContractGuardABI = new ethers.utils.Interface(Governance.abi).encodeFunctionData("setContractGuard", [
      redemptionVault,
      guardAddress,
    ]);
    await proposeTx(
      versions[config.oldTag].contracts.Governance,
      setContractGuardABI,
      "setContractGuard for MidasRedemptionVaultContractGuard",
      config,
      addresses,
    );

    const deployedGuard = {
      contractAddress: redemptionVault,
      guardName: "MidasRedemptionVaultContractGuard",
      guardAddress,
      description: "Midas Redemption Vault",
    };
    await addOrReplaceGuardInFile(filenames.contractGuardsFileName, deployedGuard, "contractAddress");
  }
};
