import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx, tryVerify } from "../../../deploymentHelpers";
import { addOrReplaceGuardInFile } from "../helpers";
import { IJob, IUpgradeConfig, IVersions, IFileNames, IAddresses, Address } from "../../../types";
import { AllowedMarketStruct } from "../../../../types/SynthetixV3SpotMarketContractGuard";

export const synthetixV3SpotMarketContractGuardJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  filenames: IFileNames,
  addresses: IAddresses,
) => {
  const synthetixV3CoreAddress = addresses.synthetixV3?.core;
  const synthetixV3SpotMarketAddress = addresses.synthetixV3?.spotMarket;
  const allowedMarkets = addresses.synthetixV3?.allowedMarkets;

  if (!synthetixV3CoreAddress || !synthetixV3SpotMarketAddress || !allowedMarkets || allowedMarkets.length === 0) {
    return console.warn("No config for SynthetixV3SpotMarketContractGuard: skipping.");
  }

  const ethers = hre.ethers;
  const Governance = await hre.artifacts.readArtifact("Governance");
  const governanceABI = new ethers.utils.Interface(Governance.abi);

  console.log("Will deploy SynthetixV3SpotMarketContractGuard");

  if (config.execute) {
    const SynthetixV3SpotMarketContractGuard = await ethers.getContractFactory("SynthetixV3SpotMarketContractGuard");
    const nftTrackerStorage = versions[config.oldTag].contracts.DhedgeNftTrackerStorageProxy;

    if (!nftTrackerStorage) {
      return console.warn("DhedgeNftTrackerStorage could not be found: skipping.");
    }

    const args: [Address, Address, AllowedMarketStruct[]] = [
      synthetixV3CoreAddress,
      synthetixV3SpotMarketAddress,
      allowedMarkets,
    ];
    const synthetixV3SpotMarketContractGuard = await SynthetixV3SpotMarketContractGuard.deploy(...args);
    await synthetixV3SpotMarketContractGuard.deployed();
    const synthetixV3ContractGuardAddress = synthetixV3SpotMarketContractGuard.address;
    console.log("SynthetixV3SpotMarketContractGuard deployed at", synthetixV3ContractGuardAddress);
    versions[config.newTag].contracts.SynthetixV3SpotMarketContractGuard = synthetixV3ContractGuardAddress;

    await tryVerify(
      hre,
      synthetixV3ContractGuardAddress,
      "contracts/guards/contractGuards/synthetixV3/SynthetixV3SpotMarketContractGuard.sol:SynthetixV3SpotMarketContractGuard",
      args,
    );

    await proposeTx(
      versions[config.oldTag].contracts.Governance,
      governanceABI.encodeFunctionData("setContractGuard", [
        synthetixV3SpotMarketAddress,
        synthetixV3ContractGuardAddress,
      ]),
      "setContractGuard for SynthetixV3SpotMarketContractGuard",
      config,
      addresses,
    );

    await addOrReplaceGuardInFile(
      filenames.contractGuardsFileName,
      {
        contractAddress: synthetixV3SpotMarketAddress,
        guardName: "SynthetixV3SpotMarketContractGuard",
        guardAddress: synthetixV3ContractGuardAddress,
        description: "Synthetix V3 Spot Market",
      },
      "contractAddress",
    );
  }
};
