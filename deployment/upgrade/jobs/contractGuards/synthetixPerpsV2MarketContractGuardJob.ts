import { HardhatRuntimeEnvironment } from "hardhat/types";
import { tryVerify } from "../../../deploymentHelpers";
import { IAddresses, IFileNames, IJob, IUpgradeConfig, IVersions } from "../../../types";

/***
 * Deploys the SynthetixPerpsV2MarketContractGuard
 */
export const synthetixPerpsV2MarketContractGuardJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  _filenames: IFileNames,
  addresses: IAddresses,
) => {
  const ethers = hre.ethers;
  if (!addresses.assets.susd) {
    console.warn("sUSD address not configured for synthetixperpsV2MarketContractGuardJob: skipping.");
    return;
  }
  if (!addresses.perpsV2?.whitelistedPools) {
    console.warn("whitelisted pools not configured for synthetixperpsV2MarketContractGuardJob: skipping.");
    return;
  }
  console.log("Will deploy synthetixperpsv2marketcontractguard");
  if (config.execute) {
    const ContractGuard = await ethers.getContractFactory("SynthetixPerpsV2MarketContractGuard");
    const args: [string, string[]] = [addresses.assets.susd, addresses.perpsV2.whitelistedPools];
    const contractGuard = await ContractGuard.deploy(...args);
    await contractGuard.deployed();
    await contractGuard.deployTransaction.wait(5);
    console.log("contract guard deployed at", contractGuard.address);

    await tryVerify(
      hre,
      contractGuard.address,
      "contracts/guards/contractGuards/SynthetixPerpsV2MarketContractGuard.sol:SynthetixPerpsV2MarketContractGuard",
      args,
    );
    versions[config.newTag].contracts.SynthetixPerpsV2MarketContractGuard = contractGuard.address;
  }
};
