import { HardhatRuntimeEnvironment } from "hardhat/types";

import { tryVerify } from "../../../deploymentHelpers";
import { IJob, IUpgradeConfig, IVersions } from "../../../types";

/***
 * Deploys ArrakisLiquidityGaugeV4ContractGuard and sets the guard for the Arrakis pool guages
 * The script will recognise if the guard hasn't been deployed before, or if it just needs to update new liquidity gauges
 */
export const arrakisLiquidityGaugeV4ContractGuardJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
) => {
  console.log("Will deploy arrakisliquiditygaugev4guard");
  if (config.execute) {
    console.log("Deploying new guard version..");
    const contractGuardAddress = await deployContractGuard(hre);
    console.log("contract guard deployed at", contractGuardAddress);

    await tryVerify(
      hre,
      contractGuardAddress,
      "contracts/guards/contractGuards/ArrakisLiquidityGaugeV4ContractGuard.sol:ArrakisLiquidityGaugeV4ContractGuard",
      [],
    );
    versions[config.newTag].contracts.ArrakisLiquidityGaugeV4ContractGuard = contractGuardAddress;
  }
};

async function deployContractGuard(hre: HardhatRuntimeEnvironment) {
  const ethers = hre.ethers;
  const ContractGuard = await ethers.getContractFactory("ArrakisLiquidityGaugeV4ContractGuard");
  const contractGuard = await ContractGuard.deploy();
  await contractGuard.deployed();
  return contractGuard.address;
}
