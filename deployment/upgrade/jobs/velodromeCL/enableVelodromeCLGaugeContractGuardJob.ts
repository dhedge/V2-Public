import { HardhatRuntimeEnvironment } from "hardhat/types";
import { IAddresses, IJob, IUpgradeConfig, IVersions, IFileNames } from "../../../types";
import { velodromeCLGaugeContractGuardJob } from "../contractGuards/velodromeCLGaugeContractGuardJob";
import { proposeContractGuardConfiguration } from "../assetContractGuardHelpers";

export const enableVelodromeCLGaugeContractGuardJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  filenames: IFileNames,
  addresses: IAddresses,
) => {
  console.log("Running enableVelodromeCLGaugeContractGuardJob");

  const guardName = "VelodromeCLGaugeContractGuard";

  if (!addresses.velodromeCL?.voter) {
    console.warn(`No velodromeCL voter configured in addresses`);
    return;
  }
  const configuredGauges = addresses.velodromeCL.enabledGauges;
  if (!configuredGauges) {
    console.warn(`No velodromeCL enabledGauges configured in addresses`);
    return;
  }

  let guardAddress = versions[config.newTag].contracts[guardName];
  if (!guardAddress) {
    await velodromeCLGaugeContractGuardJob(config, hre, versions, filenames, addresses);
    guardAddress = versions[config.newTag].contracts[guardName];
    if (!guardAddress) {
      console.warn(`No ${guardName} in versions`);
      return;
    }
  }

  const voter = await hre.ethers.getContractAt("IVelodromeV2Voter", addresses.velodromeCL.voter);
  for (const configuredGaugeAddress of configuredGauges) {
    const isGauge = await voter.isGauge(configuredGaugeAddress);
    if (!isGauge) {
      console.warn(`${configuredGaugeAddress} is not a valid gauge address, skipping`);
      continue;
    }

    await proposeContractGuardConfiguration(config, hre, versions, filenames, addresses, {
      contractAddress: configuredGaugeAddress,
      guardAddress,
      name: guardName,
    });
  }
};
