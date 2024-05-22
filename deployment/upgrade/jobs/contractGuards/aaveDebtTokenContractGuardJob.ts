import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx, tryVerify } from "../../../deploymentHelpers";
import { addOrReplaceGuardInFile } from "../helpers";
import { IJob, IUpgradeConfig, IVersions, IFileNames, IAddresses, Address } from "../../../types";

export const aaveDebtTokenContractGuardJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  filenames: IFileNames,
  addresses: IAddresses,
) => {
  if (!addresses.aaveMigrationHelper || !addresses.aaveMigrationHelper.aaveV3DebtTokensWhitelist.length) {
    return console.warn("No config for AaveDebtTokenContractGuard: skipping.");
  }

  const ethers = hre.ethers;
  const Governance = await hre.artifacts.readArtifact("Governance");
  const governanceABI = new ethers.utils.Interface(Governance.abi);

  console.log("Will deploy AaveDebtTokenContractGuard");

  if (config.execute) {
    let aaveDebtTokenContractGuardAddress = versions[config.newTag].contracts.AaveDebtTokenContractGuard;

    if (!aaveDebtTokenContractGuardAddress) {
      const AaveDebtTokenContractGuard = await ethers.getContractFactory("AaveDebtTokenContractGuard");
      const args: [Address] = [addresses.aaveMigrationHelper.migrationHelperAddress];
      const aaveDebtTokenContractGuard = await AaveDebtTokenContractGuard.deploy(...args);
      await aaveDebtTokenContractGuard.deployed();
      aaveDebtTokenContractGuardAddress = aaveDebtTokenContractGuard.address;
      console.log("AaveDebtTokenContractGuard deployed at", aaveDebtTokenContractGuardAddress);
      versions[config.newTag].contracts.AaveDebtTokenContractGuard = aaveDebtTokenContractGuardAddress;

      await tryVerify(
        hre,
        aaveDebtTokenContractGuardAddress,
        "contracts/guards/contractGuards/aaveMigrationHelper/AaveDebtTokenContractGuard.sol:AaveDebtTokenContractGuard",
        args,
      );
    }

    for (const debtToken of addresses.aaveMigrationHelper.aaveV3DebtTokensWhitelist) {
      await proposeTx(
        versions[config.oldTag].contracts.Governance,
        governanceABI.encodeFunctionData("setContractGuard", [debtToken, aaveDebtTokenContractGuardAddress]),
        `setContractGuard for ${debtToken}`,
        config,
        addresses,
      );

      await addOrReplaceGuardInFile(
        filenames.contractGuardsFileName,
        {
          contractAddress: debtToken,
          guardName: "AaveDebtTokenContractGuard",
          guardAddress: aaveDebtTokenContractGuardAddress,
          description: "Aave Debt Token Contract Guard",
        },
        "contractAddress",
      );
    }
  }
};
