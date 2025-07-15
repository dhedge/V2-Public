import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx, tryVerify } from "../../../deploymentHelpers";

import { IJob, IUpgradeConfig, IVersions, IFileNames, IAddresses } from "../../../types";
import { addOrReplaceGuardInFile } from "../helpers";
import { closedContractGuardJob } from "./closedContractGuardJob";

export const gmxExchangeRouterContractGuardJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  filenames: IFileNames,
  addresses: IAddresses,
) => {
  if (!addresses.gmx) {
    return console.warn("No config for GmxExchangeRouterContractGuard: skipping.");
  }

  const {
    approvalRouter,
    dHedgeVaultsWhitelist,
    dataStore,
    exchangeRouter,
    feeReceiver,
    reader,
    virtualTokenResolver,
    referralStorage,
  } = addresses.gmx;

  const ethers = hre.ethers;
  const Governance = await hre.artifacts.readArtifact("Governance");
  const governanceABI = new ethers.utils.Interface(Governance.abi);
  const slippageAccumulatorAddress = versions[config.oldTag].contracts.SlippageAccumulator;
  const nftTrackerStorage = versions[config.oldTag].contracts.DhedgeNftTrackerStorageProxy;
  if (!slippageAccumulatorAddress) {
    return console.warn("SlippageAccumulator could not be found: skipping.");
  }

  if (!nftTrackerStorage) {
    return console.warn("DhedgeNftTrackerStorage could not be found: skipping.");
  }

  const gmxClaimableCollateralTrackerLib = versions[config.newTag].contracts.GmxClaimableCollateralTrackerLib;

  if (!gmxClaimableCollateralTrackerLib) return console.warn("GmxClaimableCollateralTrackerLib not found: skipping.");

  console.log("Will deploy GmxExchangeRouterContractGuard");

  if (config.execute) {
    console.log("Deploying GMX libraries...");

    const GmxHelperLib = await ethers.getContractFactory("GmxHelperLib");
    const gmxHelperLib = await GmxHelperLib.deploy();
    await gmxHelperLib.deployed();
    console.log("GmxHelperLib deployed at:", gmxHelperLib.address);
    versions[config.newTag].contracts.GmxHelperLib = gmxHelperLib.address;

    await tryVerify(hre, gmxHelperLib.address, "contracts/utils/gmx/GmxHelperLib.sol:GmxHelperLib", []);

    const GmxAfterTxValidatorLib = await ethers.getContractFactory("GmxAfterTxValidatorLib", {
      libraries: {
        GmxClaimableCollateralTrackerLib: gmxClaimableCollateralTrackerLib,
      },
    });
    const gmxAfterTxValidatorLib = await GmxAfterTxValidatorLib.deploy();
    await gmxAfterTxValidatorLib.deployed();
    console.log("GmxAfterTxValidatorLib deployed at:", gmxAfterTxValidatorLib.address);
    versions[config.newTag].contracts.GmxAfterTxValidatorLib = gmxAfterTxValidatorLib.address;

    await tryVerify(
      hre,
      gmxAfterTxValidatorLib.address,
      "contracts/utils/gmx/GmxAfterTxValidatorLib.sol:GmxAfterTxValidatorLib",
      [],
    );

    const GmxAfterExcutionLib = await ethers.getContractFactory("GmxAfterExcutionLib", {
      libraries: {
        GmxAfterTxValidatorLib: gmxAfterTxValidatorLib.address,
        GmxClaimableCollateralTrackerLib: gmxClaimableCollateralTrackerLib,
      },
    });
    const gmxAfterExcutionLib = await GmxAfterExcutionLib.deploy();
    await gmxAfterExcutionLib.deployed();
    console.log("GmxAfterExcutionLib deployed at:", gmxAfterExcutionLib.address);
    versions[config.newTag].contracts.GmxAfterExcutionLib = gmxAfterExcutionLib.address;

    await tryVerify(
      hre,
      gmxAfterExcutionLib.address,
      "contracts/utils/gmx/GmxAfterExcutionLib.sol:GmxAfterExcutionLib",
      [],
    );

    const GmxExchangeRouterContractGuard = await ethers.getContractFactory("GmxExchangeRouterContractGuard", {
      libraries: {
        GmxHelperLib: gmxHelperLib.address,
        GmxAfterTxValidatorLib: gmxAfterTxValidatorLib.address,
        GmxAfterExcutionLib: gmxAfterExcutionLib.address,
      },
    });

    const args: Parameters<typeof GmxExchangeRouterContractGuard.deploy> = [
      {
        dataStore,
        feeReceiver,
        reader,
        gmxExchangeRouter: exchangeRouter,
        referralStorage,
      },
      dHedgeVaultsWhitelist,
      virtualTokenResolver,
      slippageAccumulatorAddress,
      nftTrackerStorage,
    ];

    const gmxExchangeRouterContractGuard = await GmxExchangeRouterContractGuard.deploy(...args);
    await gmxExchangeRouterContractGuard.deployed();
    const gmxExchangeRouterContractGuardAddress = gmxExchangeRouterContractGuard.address;
    console.log("gmxExchangeRouterContractGuard deployed at", gmxExchangeRouterContractGuardAddress);
    versions[config.newTag].contracts.GmxExchangeRouterContractGuard = gmxExchangeRouterContractGuardAddress;

    await tryVerify(
      hre,
      gmxExchangeRouterContractGuardAddress,
      "contracts/guards/contractGuards/gmx/GmxExchangeRouterContractGuard.sol:GmxExchangeRouterContractGuard",
      args,
    );

    await proposeTx(
      versions[config.oldTag].contracts.Governance,
      governanceABI.encodeFunctionData("setContractGuard", [exchangeRouter, gmxExchangeRouterContractGuardAddress]),
      "setContractGuard for GmxExchangeRouterContractGuard",
      config,
      addresses,
    );

    await addOrReplaceGuardInFile(
      filenames.contractGuardsFileName,
      {
        contractAddress: exchangeRouter,
        guardName: "GmxExchangeRouterContractGuard",
        guardAddress: gmxExchangeRouterContractGuardAddress,
        description: "Gmx Exchange Router Guard",
      },
      "contractAddress",
    );

    if (!versions[config.oldTag].contracts.ClosedContractGuard) {
      await closedContractGuardJob(config, hre, versions, filenames, addresses);
    }

    const governance = await ethers.getContractAt("Governance", versions[config.oldTag].contracts.Governance);
    const approvalRouterGuardSet = await governance.contractGuards(approvalRouter);

    if (approvalRouterGuardSet.toLowerCase() !== versions[config.newTag].contracts.ClosedContractGuard?.toLowerCase()) {
      await proposeTx(
        versions[config.oldTag].contracts.Governance,
        governanceABI.encodeFunctionData("setContractGuard", [
          approvalRouter,
          versions[config.oldTag].contracts.ClosedContractGuard,
        ]),
        "setContractGuard for GMX Approval Router",
        config,
        addresses,
      );

      await addOrReplaceGuardInFile(
        filenames.contractGuardsFileName,
        {
          contractAddress: approvalRouter,
          guardName: "ClosedContractGuard",
          guardAddress: versions[config.oldTag].contracts.ClosedContractGuard as string,
          description: "GMX Approval Router Contract Guard",
        },
        "contractAddress",
      );
    }
  }
};
