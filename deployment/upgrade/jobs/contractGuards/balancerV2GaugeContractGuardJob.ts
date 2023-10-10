import { HardhatRuntimeEnvironment } from "hardhat/types";
import { tryVerify } from "../../../deploymentHelpers";
import { IJob, IUpgradeConfig, IVersions } from "../../../types";

/***
 * Deploys the BalancerV2GaugeContractGuard
 */
export const balancerV2GaugeContractGuardJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  // TODO: This optimally should not be mutated
  versions: IVersions,
) => {
  const ethers = hre.ethers;

  console.log("Will deploy balancerv2gaugecontractguardjob");
  if (config.execute) {
    const ContractGuard = await ethers.getContractFactory("BalancerV2GaugeContractGuard");
    const contractGuard = await ContractGuard.deploy();
    await contractGuard.deployed();
    console.log("contract guard deployed at", contractGuard.address);
    await contractGuard.deployTransaction.wait(5);
    await tryVerify(
      hre,
      contractGuard.address,
      "contracts/guards/contractGuards/BalancerV2GaugeContractGuard.sol:BalancerV2GaugeContractGuard",
      [],
    );
    versions[config.newTag].contracts.BalancerV2GaugeContractGuard = contractGuard.address;
  }
};
