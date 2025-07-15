import { HardhatRuntimeEnvironment } from "hardhat/types";

import { proposeTx, tryVerify } from "../../../deploymentHelpers";
import { IDeployedContractGuard, IJob, IUpgradeConfig, IVersions, IFileNames, IAddresses } from "../../../types";
import { addOrReplaceGuardInFile } from "../helpers";

export const angleDistributorContractGuardJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  filenames: IFileNames,
  addresses: IAddresses,
) => {
  const ethers = hre.ethers;

  console.log("Will deploy AngleDistributorContractGuard");

  const angleProtocolDistributor = addresses.angleProtocol?.distributor;
  const rewardTokenSupported = addresses.angleProtocol?.rewardTokenSupported;
  const aaveV3LendingPool = addresses.aaveV3?.aaveLendingPoolAddress;

  if (!angleProtocolDistributor || !rewardTokenSupported || !aaveV3LendingPool)
    return console.warn("AngleDistributorContractGuard not configured: skipping.");

  if (config.execute) {
    const AngleDistributorContractGuard = await ethers.getContractFactory("AngleDistributorContractGuard");
    const args: Parameters<typeof AngleDistributorContractGuard.deploy> = [aaveV3LendingPool, rewardTokenSupported];
    const angleDistributorContractGuard = await AngleDistributorContractGuard.deploy(...args);
    await angleDistributorContractGuard.deployed();
    const angleDistributorContractGuardAddress = angleDistributorContractGuard.address;

    console.log("AngleDistributorContractGuard deployed at: ", angleDistributorContractGuardAddress);

    versions[config.newTag].contracts.AngleDistributorContractGuard = angleDistributorContractGuardAddress;

    await tryVerify(
      hre,
      angleDistributorContractGuardAddress,
      "contracts/guards/contractGuards/AngleDistributorContractGuard.sol:AngleDistributorContractGuard",
      args,
    );

    const Governance = await hre.artifacts.readArtifact("Governance");
    await proposeTx(
      versions[config.oldTag].contracts.Governance,
      new ethers.utils.Interface(Governance.abi).encodeFunctionData("setContractGuard", [
        angleProtocolDistributor,
        angleDistributorContractGuardAddress,
      ]),
      "setContractGuard for AngleDistributor",
      config,
      addresses,
    );

    const deployedGuard: IDeployedContractGuard = {
      contractAddress: angleProtocolDistributor,
      guardName: "AngleDistributorContractGuard",
      guardAddress: angleDistributorContractGuardAddress,
      description: "Angle Protocol Distributor - claim rewards",
    };
    await addOrReplaceGuardInFile(filenames.contractGuardsFileName, deployedGuard, "contractAddress");
  }
};
