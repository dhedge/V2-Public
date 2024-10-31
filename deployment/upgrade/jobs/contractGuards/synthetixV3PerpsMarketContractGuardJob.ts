import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx, tryVerify } from "../../../deploymentHelpers";
import { addOrReplaceGuardInFile } from "../helpers";
import { IJob, IUpgradeConfig, IVersions, IFileNames, IAddresses, Address } from "../../../types";

export const synthetixV3PerpsMarketContractGuardJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  filenames: IFileNames,
  addresses: IAddresses,
) => {
  const synthetixV3CoreAddress = addresses.synthetixV3?.core;
  const synthetixV3PerpsMarketAddress = addresses.synthetixV3?.perpsMarket;

  if (!synthetixV3CoreAddress || !synthetixV3PerpsMarketAddress) {
    return console.warn("No config for SynthetixV3PerpsMarketContractGuard: skipping.");
  }

  const ethers = hre.ethers;
  const Governance = await hre.artifacts.readArtifact("Governance");
  const governanceABI = new ethers.utils.Interface(Governance.abi);

  console.log("Will deploy SynthetixV3PerpsMarketContractGuard");

  if (config.execute) {
    const SynthetixV3PerpsMarketContractGuard = await ethers.getContractFactory("SynthetixV3PerpsMarketContractGuard");

    const nftTrackerStorage = versions[config.oldTag].contracts.DhedgeNftTrackerStorageProxy;

    if (!nftTrackerStorage) {
      return console.warn("DhedgeNftTrackerStorage could not be found: skipping.");
    }

    const args: [Address, Address] = [nftTrackerStorage, synthetixV3CoreAddress];

    const synthetixV3PerpsMarketContractGuard = await SynthetixV3PerpsMarketContractGuard.deploy(...args);
    await synthetixV3PerpsMarketContractGuard.deployed();
    const synthetixV3ContractGuardAddress = synthetixV3PerpsMarketContractGuard.address;
    console.log("synthetixV3PerpsMarketContractGuard deployed at", synthetixV3ContractGuardAddress);
    versions[config.newTag].contracts.SynthetixV3PerpsMarketContractGuard = synthetixV3ContractGuardAddress;

    await tryVerify(
      hre,
      synthetixV3ContractGuardAddress,
      "contracts/guards/contractGuards/synthetixV3/SynthetixV3PerpsMarketContractGuard.sol:SynthetixV3PerpsMarketContractGuard",
      args,
    );

    await proposeTx(
      versions[config.oldTag].contracts.Governance,
      governanceABI.encodeFunctionData("setContractGuard", [
        synthetixV3PerpsMarketAddress,
        synthetixV3ContractGuardAddress,
      ]),
      "setContractGuard for SynthetixV3PerpsMarketContractGuard",
      config,
      addresses,
    );

    await addOrReplaceGuardInFile(
      filenames.contractGuardsFileName,
      {
        contractAddress: synthetixV3PerpsMarketAddress,
        guardName: "SynthetixV3PerpsMarketContractGuard",
        guardAddress: synthetixV3ContractGuardAddress,
        description: "Synthetix V3 Perps Market",
      },
      "contractAddress",
    );
  }
};
