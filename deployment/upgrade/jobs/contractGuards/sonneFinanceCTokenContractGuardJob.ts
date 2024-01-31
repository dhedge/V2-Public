import { HardhatRuntimeEnvironment } from "hardhat/types";
import { tryVerify } from "../../../deploymentHelpers";
import { IAddresses, IJob, IUpgradeConfig, IVersions, IFileNames } from "../../../types";

// This job deploys the SonneFinanceCTokenGuard contract and adds it to the contract guards file.
// Note that to support usage of any cToken in dHEDGE, we have to assign this guard as a contract guard to the cToken.
export const sonneFinanceCTokenContractGuardJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  _: IFileNames,
  addresses: IAddresses,
) => {
  const ethers = hre.ethers;

  console.log("Will deploy SonneFinanceCTokenContractGuard");

  if (!addresses.sonneFinance?.dHedgeVaultsWhitelist || addresses.sonneFinance.dHedgeVaultsWhitelist.length === 0) {
    return console.warn("dHedgeVaultsWhitelist addresses could not be found: skipping.");
  }

  if (config.execute) {
    const args: [typeof addresses.sonneFinance.dHedgeVaultsWhitelist] = [addresses.sonneFinance.dHedgeVaultsWhitelist];
    const SonneFinanceCTokenGuard = await ethers.getContractFactory("SonneFinanceCTokenGuard");
    const sonneFinanceCTokenGuard = await SonneFinanceCTokenGuard.deploy(...args);
    await sonneFinanceCTokenGuard.deployed();

    console.log("SonneFinanceCTokenGuard deployed at", sonneFinanceCTokenGuard.address);
    versions[config.newTag].contracts.SonneFinanceCTokenGuard = sonneFinanceCTokenGuard.address;

    await tryVerify(
      hre,
      sonneFinanceCTokenGuard.address,
      "contracts/guards/contractGuards/sonne/SonneFinanceCTokenGuard.sol:SonneFinanceCTokenGuard",
      args,
    );
  }
};
