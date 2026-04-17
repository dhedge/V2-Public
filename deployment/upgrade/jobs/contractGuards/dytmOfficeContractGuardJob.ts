import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx, tryVerify } from "../../../deploymentHelpers";
import { addOrReplaceGuardInFile } from "../helpers";
import { IJob, IUpgradeConfig, IVersions, IFileNames, IAddresses, Address } from "../../../types";

export const dytmOfficeContractGuardJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  filenames: IFileNames,
  addresses: IAddresses,
) => {
  if (!addresses.dytm) {
    return console.warn("dytm config not found for dytmOfficeContractGuardJob: skipping.");
  }

  const { dytmOffice, dytmPeriphery, whitelistedPools, whitelistedMarkets, maxDytmMarkets } = addresses.dytm;

  console.log("Will deploy DytmOfficeContractGuard");

  if (config.execute) {
    const ethers = hre.ethers;
    const poolFactoryAddress = versions[config.oldTag].contracts.PoolFactoryProxy;
    const nftTrackerAddress = versions[config.oldTag].contracts.DhedgeNftTrackerStorageProxy;

    if (!poolFactoryAddress) {
      return console.warn("PoolFactoryProxy could not be found: skipping.");
    }
    if (!nftTrackerAddress) {
      return console.warn("DhedgeNftTrackerStorageProxy could not be found: skipping.");
    }

    const DytmOfficeContractGuard = await ethers.getContractFactory("DytmOfficeContractGuard");

    const dytmConfig = {
      dytmOffice,
      dytmPeriphery,
      dhedgePoolFactory: poolFactoryAddress,
      nftTracker: nftTrackerAddress,
      maxDytmMarkets,
    };

    const args: [Address[], number[], typeof dytmConfig] = [whitelistedPools, whitelistedMarkets, dytmConfig];
    const dytmOfficeContractGuard = await DytmOfficeContractGuard.deploy(...args);
    await dytmOfficeContractGuard.deployed();
    const dytmOfficeContractGuardAddress = dytmOfficeContractGuard.address;

    console.log("DytmOfficeContractGuard deployed at", dytmOfficeContractGuardAddress);
    versions[config.newTag].contracts.DytmOfficeContractGuard = dytmOfficeContractGuardAddress;

    await tryVerify(
      hre,
      dytmOfficeContractGuardAddress,
      "contracts/guards/contractGuards/dytm/DytmOfficeContractGuard.sol:DytmOfficeContractGuard",
      args,
    );

    const Governance = await hre.artifacts.readArtifact("Governance");
    const setContractGuardABI = new ethers.utils.Interface(Governance.abi).encodeFunctionData("setContractGuard", [
      dytmOffice,
      dytmOfficeContractGuardAddress,
    ]);

    await proposeTx(
      versions[config.oldTag].contracts.Governance,
      setContractGuardABI,
      "setContractGuard for DytmOfficeContractGuard",
      config,
      addresses,
    );

    const deployedGuard = {
      contractAddress: dytmOffice,
      guardName: "DytmOfficeContractGuard",
      guardAddress: dytmOfficeContractGuardAddress,
      description: "DYTM Office",
    };

    await addOrReplaceGuardInFile(filenames.contractGuardsFileName, deployedGuard, "contractAddress");
  }
};
