import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx, tryVerify } from "../../../deploymentHelpers";
import { addOrReplaceGuardInFile } from "../helpers";
import { IJob, IUpgradeConfig, IVersions, IFileNames, IAddresses, Address } from "../../../types";

export const dytmOfficeContractGuardJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  filenames: IFileNames,
  addresses: IAddresses,
) => {
  if (!addresses.dytm) {
    return console.warn("dytm config not found for dytmOfficeContractGuardJob: skipping.");
  }

  const { dytmOffice, dytmPeriphery, accountSplitterAndMerger, whitelistedPools, whitelistedMarkets, maxDytmMarkets } =
    addresses.dytm;

  console.log("Will deploy DytmOfficeContractGuard");

  if (config.execute) {
    const ethers = hre.ethers;
    const poolFactoryAddress = versions[config.oldTag].contracts.PoolFactoryProxy;
    const nftTrackerAddress = versions[config.oldTag].contracts.DhedgeNftTrackerStorageProxy;

    if (!poolFactoryAddress) {
      return console.warn("PoolFactoryProxy could not be found: skipping.");
    }
    if (!nftTrackerAddress) {
      return console.warn("DhedgeNftTrackerStorageProxy could not be found: skipping.");
    }

    // Whitelist drift check before redeploy:
    // - the new guard seeds its whitelist from deploymentData `whitelistedPools` only
    // - pools added post-deploy via setPoolsWhitelist exist only on-chain
    // - abort if config is missing any on-chain pool, otherwise they'd be silently dropped
    const oldGuardAddress = versions[config.oldTag].contracts.DytmOfficeContractGuard;
    if (oldGuardAddress) {
      const oldGuard = await ethers.getContractAt("DytmOfficeContractGuard", oldGuardAddress);
      let onChainPools: string[] | undefined;
      try {
        onChainPools = await oldGuard.getWhitelistedPools();
      } catch (error) {
        // Only the legacy guard (predates getWhitelistedPools, can't drift: no setter) is allowed through;
        // rethrow RPC/unexpected errors so they abort the deploy instead of skipping the check.
        // CALL_EXCEPTION here can only mean the method is missing: on guards that have it,
        // getWhitelistedPools is a view with no revert path.
        if ((error as { code?: string }).code !== "CALL_EXCEPTION") throw error;
        console.warn(
          `ACTION: existing DytmOfficeContractGuard (${oldGuardAddress}) predates getWhitelistedPools(); ` +
            `cannot auto-verify — manually confirm deploymentData dytm.whitelistedPools is complete before redeploying.`,
        );
      }
      if (onChainPools) {
        const configSet = new Set(whitelistedPools.map((pool) => pool.toLowerCase()));
        const missing = onChainPools.filter((pool) => !configSet.has(pool.toLowerCase()));
        if (missing.length > 0) {
          console.warn("On-chain whitelisted pools:", onChainPools);
          console.warn("deploymentData dytm.whitelistedPools:", whitelistedPools);
          throw new Error(
            `ABORT: deploymentData dytm.whitelistedPools is missing ${missing.length} pool(s) currently ` +
              `whitelisted on-chain: ${missing.join(", ")}. Add them to the dytm.whitelistedPools config ` +
              `before redeploying or they will be dropped.`,
          );
        }
      }
    }

    const DytmOfficeContractGuard = await ethers.getContractFactory("DytmOfficeContractGuard");

    const dytmConfig = {
      dytmOffice,
      dytmPeriphery,
      dhedgePoolFactory: poolFactoryAddress,
      nftTracker: nftTrackerAddress,
      accountSplitterAndMerger,
      maxDytmMarkets,
      admin: addresses.protocolDaoAddress,
    };

    const args: [Address[], number[], typeof dytmConfig] = [whitelistedPools, whitelistedMarkets, dytmConfig];
    const dytmOfficeContractGuard = await DytmOfficeContractGuard.deploy(...args);
    await dytmOfficeContractGuard.deployed();
    const dytmOfficeContractGuardAddress = dytmOfficeContractGuard.address;

    console.log("DytmOfficeContractGuard deployed at", dytmOfficeContractGuardAddress);
    versions[config.newTag].contracts.DytmOfficeContractGuard = dytmOfficeContractGuardAddress;

    await tryVerify(
      hre,
      dytmOfficeContractGuardAddress,
      "contracts/guards/contractGuards/dytm/DytmOfficeContractGuard.sol:DytmOfficeContractGuard",
      args,
    );

    const Governance = await hre.artifacts.readArtifact("Governance");
    const setContractGuardABI = new ethers.utils.Interface(Governance.abi).encodeFunctionData("setContractGuard", [
      dytmOffice,
      dytmOfficeContractGuardAddress,
    ]);

    await proposeTx(
      versions[config.oldTag].contracts.Governance,
      setContractGuardABI,
      "setContractGuard for DytmOfficeContractGuard",
      config,
      addresses,
    );

    const deployedGuard = {
      contractAddress: dytmOffice,
      guardName: "DytmOfficeContractGuard",
      guardAddress: dytmOfficeContractGuardAddress,
      description: "DYTM Office",
    };

    await addOrReplaceGuardInFile(filenames.contractGuardsFileName, deployedGuard, "contractAddress");
  }
};
