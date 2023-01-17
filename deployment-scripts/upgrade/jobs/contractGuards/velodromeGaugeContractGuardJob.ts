import { HardhatRuntimeEnvironment } from "hardhat/types";
import { tryVerify } from "../../../Helpers";
import { IJob, IUpgradeConfig, IVersions } from "../../../types";

/***
 * Deploys the VelodromeGaugeContractGuard
 */
export const velodromeGaugeContractGuardJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  // TODO: This optimally should not be mutated
  versions: IVersions,
) => {
  const ethers = hre.ethers;

  console.log("Will deploy velodromegaugecontractguardjob");
  if (config.execute) {
    const ContractGuard = await ethers.getContractFactory("VelodromeGaugeContractGuard");
    const contractGuard = await ContractGuard.deploy();
    await contractGuard.deployed();
    console.log("contract guard deployed at", contractGuard.address);

    await tryVerify(
      hre,
      contractGuard.address,
      "contracts/guards/contractGuards/VelodromeGaugeContractGuard.sol:VelodromeGaugeContractGuard",
      [],
    );
    versions[config.newTag].contracts.VelodromeGaugeContractGuard = contractGuard.address;
  }
};
