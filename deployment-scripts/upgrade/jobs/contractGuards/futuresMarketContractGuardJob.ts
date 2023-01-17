import { HardhatRuntimeEnvironment } from "hardhat/types";
import { tryVerify } from "../../../Helpers";
import { IJob, IUpgradeConfig, IVersions } from "../../../types";

/***
 * Deploys the FuturesMarketContractGuard
 */
export const futuresMarketContractGuardJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
) => {
  const ethers = hre.ethers;

  console.log("Will deploy futuresmarketcontractguardjob");
  if (config.execute) {
    const ContractGuard = await ethers.getContractFactory("FuturesMarketContractGuard");
    const contractGuard = await ContractGuard.deploy();
    await contractGuard.deployed();
    await contractGuard.deployTransaction.wait(5);
    console.log("contract guard deployed at", contractGuard.address);

    await tryVerify(
      hre,
      contractGuard.address,
      "contracts/guards/contractGuards/FuturesMarketContractGuard.sol:FuturesMarketContractGuard",
      [],
    );
    versions[config.newTag].contracts.FuturesMarketContractGuard = contractGuard.address;
  }
};
