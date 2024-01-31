import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx, tryVerify } from "../../../deploymentHelpers";
import { IAddresses, IJob, IUpgradeConfig, IVersions, IFileNames } from "../../../types";
import { addOrReplaceGuardInFile } from "../helpers";

export const sonneFinanceComptrollerContractGuardJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  filenames: IFileNames,
  addresses: IAddresses,
) => {
  const ethers = hre.ethers;
  const Governance = await hre.artifacts.readArtifact("Governance");
  const governanceABI = new ethers.utils.Interface(Governance.abi);

  console.log("Will deploy SonneFinanceComptrollerContractGuard");

  if (!addresses.sonneFinance?.comptroller) return console.warn("Sonne Finance Comptroller address not found");

  if (config.execute) {
    const SonneFinanceComptrollerGuard = await ethers.getContractFactory("SonneFinanceComptrollerGuard");
    const sonneFinanceComptrollerGuard = await SonneFinanceComptrollerGuard.deploy();
    await sonneFinanceComptrollerGuard.deployed();

    console.log("SonneFinanceComptrollerGuard deployed at", sonneFinanceComptrollerGuard.address);
    versions[config.newTag].contracts.SonneFinanceComptrollerGuard = sonneFinanceComptrollerGuard.address;

    await tryVerify(
      hre,
      sonneFinanceComptrollerGuard.address,
      "contracts/guards/contractGuards/sonne/SonneFinanceComptrollerGuard.sol:SonneFinanceComptrollerGuard",
      [],
    );

    const setContractGuardABI = governanceABI.encodeFunctionData("setContractGuard", [
      addresses.sonneFinance.comptroller,
      sonneFinanceComptrollerGuard.address,
    ]);

    await proposeTx(
      versions[config.oldTag].contracts.Governance,
      setContractGuardABI,
      "setContractGuard for Sonne Finance Comptroller",
      config,
      addresses,
    );

    const deployedGuard = {
      contractAddress: addresses.sonneFinance.comptroller,
      guardName: "SonneFinanceComptrollerGuard",
      guardAddress: sonneFinanceComptrollerGuard.address,
      description: "Sonne Finance Comptroller Guard",
    };
    await addOrReplaceGuardInFile(filenames.contractGuardsFileName, deployedGuard, "contractAddress");
  }
};
