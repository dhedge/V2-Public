import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx, tryVerify } from "../../../deploymentHelpers";
import { addOrReplaceGuardInFile } from "../helpers";
import { IJob, IUpgradeConfig, IVersions, IFileNames, IAddresses, Address } from "../../../types";

export const aaveMigrationHelperGuardJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  filenames: IFileNames,
  addresses: IAddresses,
) => {
  if (
    !addresses.aaveMigrationHelper ||
    !addresses.aaveV3 ||
    !addresses.aaveMigrationHelper.dHedgeVaultsWhitelist.length
  ) {
    return console.warn("No config for AaveMigrationHelperGuard: skipping.");
  }

  const ethers = hre.ethers;
  const Governance = await hre.artifacts.readArtifact("Governance");
  const governanceABI = new ethers.utils.Interface(Governance.abi);

  console.log("Will deploy AaveMigrationHelperGuard");

  if (config.execute) {
    const AaveMigrationHelperGuard = await ethers.getContractFactory("AaveMigrationHelperGuard");
    const args: [Address[], Address] = [
      addresses.aaveMigrationHelper.dHedgeVaultsWhitelist,
      addresses.aaveV3.aaveLendingPoolAddress,
    ];
    const aaveMigrationHelperGuard = await AaveMigrationHelperGuard.deploy(...args);
    await aaveMigrationHelperGuard.deployed();
    const aveMigrationHelperGuardAddress = aaveMigrationHelperGuard.address;
    console.log("AaveMigrationHelperGuard deployed at", aveMigrationHelperGuardAddress);
    versions[config.newTag].contracts.AaveMigrationHelperGuard = aveMigrationHelperGuardAddress;

    await tryVerify(
      hre,
      aveMigrationHelperGuardAddress,
      "contracts/guards/contractGuards/aaveMigrationHelper/AaveMigrationHelperGuard.sol:AaveMigrationHelperGuard",
      args,
    );

    await proposeTx(
      versions[config.oldTag].contracts.Governance,
      governanceABI.encodeFunctionData("setContractGuard", [
        addresses.aaveMigrationHelper.migrationHelperAddress,
        aveMigrationHelperGuardAddress,
      ]),
      "setContractGuard for AaveMigrationHelper",
      config,
      addresses,
    );

    await addOrReplaceGuardInFile(
      filenames.contractGuardsFileName,
      {
        contractAddress: addresses.aaveMigrationHelper.migrationHelperAddress,
        guardName: "AaveMigrationHelperGuard",
        guardAddress: aveMigrationHelperGuardAddress,
        description: "Aave Migration Helper",
      },
      "contractAddress",
    );
  }
};
