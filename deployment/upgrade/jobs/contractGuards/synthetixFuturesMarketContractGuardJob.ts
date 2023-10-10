import { HardhatRuntimeEnvironment } from "hardhat/types";
import { tryVerify } from "../../../deploymentHelpers";
import { IJob, IUpgradeConfig, IVersions } from "../../../types";

/***
 * Deploys the SynthetixFuturesMarketContractGuard
 */
export const synthetixFuturesMarketContractGuardJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
) => {
  const ethers = hre.ethers;

  console.log("Will deploy synthetixfuturesmarketcontractguardjob");
  if (config.execute) {
    const ContractGuard = await ethers.getContractFactory("SynthetixFuturesMarketContractGuard");
    const contractGuard = await ContractGuard.deploy();
    await contractGuard.deployed();
    await contractGuard.deployTransaction.wait(5);
    console.log("contract guard deployed at", contractGuard.address);

    await tryVerify(
      hre,
      contractGuard.address,
      "contracts/guards/contractGuards/SynthetixFuturesMarketContractGuard.sol:SynthetixFuturesMarketContractGuard",
      [],
    );
    versions[config.newTag].contracts.SynthetixFuturesMarketContractGuard = contractGuard.address;
  }
};
