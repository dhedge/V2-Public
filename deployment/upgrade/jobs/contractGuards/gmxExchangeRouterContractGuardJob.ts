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
  const gmxHelperLib = versions[config.newTag].contracts.GmxHelperLib;

  if (!gmxHelperLib) return console.warn("GmxHelperLib not found: skipping.");
  if (!gmxClaimableCollateralTrackerLib) return console.warn("GmxClaimableCollateralTrackerLib not found: skipping.");

  console.log("Will deploy GmxExchangeRouterContractGuard");

  if (config.execute) {
    console.log("Deploying GMX libraries...");

    const GmxAfterTxValidatorLib = await ethers.getContractFactory("GmxAfterTxValidatorLib", {
      libraries: {
        GmxHelperLib: gmxHelperLib,
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

    const GmxEventUtils = await ethers.getContractFactory("GmxEventUtils");
    const gmxEventUtils = await GmxEventUtils.deploy();
    await gmxEventUtils.deployed();
    console.log("GmxEventUtils deployed at:", gmxEventUtils.address);
    versions[config.newTag].contracts.GmxEventUtils = gmxEventUtils.address;

    await tryVerify(hre, gmxEventUtils.address, "contracts/utils/gmx/GmxEventUtils.sol:GmxEventUtils", []);

    const GmxAfterExecutionLib = await ethers.getContractFactory("GmxAfterExecutionLib", {
      libraries: {
        GmxAfterTxValidatorLib: gmxAfterTxValidatorLib.address,
        GmxClaimableCollateralTrackerLib: gmxClaimableCollateralTrackerLib,
        GmxEventUtils: gmxEventUtils.address,
        GmxHelperLib: gmxHelperLib,
      },
    });
    const gmxAfterExecutionLib = await GmxAfterExecutionLib.deploy();
    await gmxAfterExecutionLib.deployed();
    console.log("GmxAfterExecutionLib deployed at:", gmxAfterExecutionLib.address);
    versions[config.newTag].contracts.GmxAfterExecutionLib = gmxAfterExecutionLib.address;

    await tryVerify(
      hre,
      gmxAfterExecutionLib.address,
      "contracts/utils/gmx/GmxAfterExecutionLib.sol:GmxAfterExecutionLib",
      [],
    );

    const GmxExchangeRouterContractGuard = await ethers.getContractFactory("GmxExchangeRouterContractGuard", {
      libraries: {
        GmxHelperLib: versions[config.newTag].contracts.GmxHelperLib as string,
        GmxAfterTxValidatorLib: versions[config.newTag].contracts.GmxAfterTxValidatorLib as string,
        GmxAfterExecutionLib: versions[config.newTag].contracts.GmxAfterExecutionLib as string,
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
