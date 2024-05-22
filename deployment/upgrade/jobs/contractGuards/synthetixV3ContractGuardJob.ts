import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx, tryVerify } from "../../../deploymentHelpers";
import { addOrReplaceGuardInFile } from "../helpers";
import { IJob, IUpgradeConfig, IVersions, IFileNames, IAddresses, Address } from "../../../types";

export const synthetixV3ContractGuardJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  filenames: IFileNames,
  addresses: IAddresses,
) => {
  const synthetixV3CoreAddress = addresses.synthetixV3?.core;

  if (!synthetixV3CoreAddress) {
    return console.warn("Synthetix V3 Core address not configured for SynthetixV3ContractGuard: skipping.");
  }

  const ethers = hre.ethers;
  const Governance = await hre.artifacts.readArtifact("Governance");
  const governanceABI = new ethers.utils.Interface(Governance.abi);

  console.log("Will deploy SynthetixV3ContractGuard");

  if (config.execute) {
    let weeklyWindowsHelperAddress = versions[config.newTag].contracts.WeeklyWindowsHelper;

    if (!weeklyWindowsHelperAddress) {
      const WeeklyWindowsHelper = await ethers.getContractFactory("WeeklyWindowsHelper");
      const weeklyWindowsHelper = await WeeklyWindowsHelper.deploy();
      await weeklyWindowsHelper.deployed();
      weeklyWindowsHelperAddress = weeklyWindowsHelper.address;
      await tryVerify(
        hre,
        weeklyWindowsHelperAddress,
        "contracts/utils/synthetixV3/libraries/WeeklyWindowsHelper.sol:WeeklyWindowsHelper",
        [],
      );
      versions[config.newTag].contracts.WeeklyWindowsHelper = weeklyWindowsHelperAddress;
    }

    const SynthetixV3ContractGuard = await ethers.getContractFactory("SynthetixV3ContractGuard", {
      libraries: {
        WeeklyWindowsHelper: weeklyWindowsHelperAddress,
      },
    });
    const nftTrackerStorage = versions[config.oldTag].contracts.DhedgeNftTrackerStorageProxy;

    if (!nftTrackerStorage) {
      return console.warn("DhedgeNftTrackerStorage could not be found: skipping.");
    }

    if (!addresses.synthetixV3?.dHedgeVaultsWhitelist || addresses.synthetixV3.dHedgeVaultsWhitelist.length === 0) {
      return console.warn("dHedgeVaultsWhitelist addresses could not be found: skipping.");
    }

    if (!addresses.synthetixV3?.windows) {
      return console.warn("windows could not be found: skipping.");
    }

    const args: [
      Address,
      typeof addresses.synthetixV3.dHedgeVaultsWhitelist,
      Address,
      typeof addresses.synthetixV3.windows,
      typeof addresses.synthetixV3.withdrawalLimit,
    ] = [
      nftTrackerStorage,
      addresses.synthetixV3.dHedgeVaultsWhitelist,
      synthetixV3CoreAddress,
      addresses.synthetixV3.windows,
      addresses.synthetixV3.withdrawalLimit,
    ];
    const synthetixV3ContractGuard = await SynthetixV3ContractGuard.deploy(...args);
    await synthetixV3ContractGuard.deployed();
    const synthetixV3ContractGuardAddress = synthetixV3ContractGuard.address;
    console.log("SynthetixV3ContractGuard deployed at", synthetixV3ContractGuardAddress);
    versions[config.newTag].contracts.SynthetixV3ContractGuard = synthetixV3ContractGuardAddress;

    await tryVerify(
      hre,
      synthetixV3ContractGuardAddress,
      "contracts/guards/contractGuards/synthetixV3/SynthetixV3ContractGuard.sol:SynthetixV3ContractGuard",
      args,
    );

    await proposeTx(
      versions[config.oldTag].contracts.Governance,
      governanceABI.encodeFunctionData("setContractGuard", [synthetixV3CoreAddress, synthetixV3ContractGuardAddress]),
      "setContractGuard for SynthetixV3ContractGuard",
      config,
      addresses,
    );

    await addOrReplaceGuardInFile(
      filenames.contractGuardsFileName,
      {
        contractAddress: synthetixV3CoreAddress,
        guardName: "SynthetixV3ContractGuard",
        guardAddress: synthetixV3ContractGuardAddress,
        description: "Synthetix V3 Core",
      },
      "contractAddress",
    );
  }
};
