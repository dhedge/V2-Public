import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx, tryVerify } from "../../../deploymentHelpers";
import { IJob, IAddresses, IUpgradeConfig, IVersions, IFileNames, Address } from "../../../types";
import { addOrReplaceGuardInFile } from "../helpers";
import { AssetType } from "../assetsJob";

export const dytmOfficeAssetGuardJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  filenames: IFileNames,
  addresses: IAddresses,
) => {
  if (!addresses.dytm) {
    return console.warn("dytm config not found for dytmOfficeAssetGuardJob: skipping.");
  }

  console.log("Will deploy DytmOfficeAssetGuard");

  if (config.execute) {
    const ethers = hre.ethers;
    const poolFactoryAddress = versions[config.oldTag].contracts.PoolFactoryProxy;
    const pendleStaticRouter = addresses.pendle?.staticRouter;
    const dytmWithdrawProcessorAddress = versions[config.oldTag].contracts.DytmWithdrawProcessor;

    if (!poolFactoryAddress) {
      return console.warn("PoolFactoryProxy could not be found: skipping.");
    }
    if (!pendleStaticRouter) {
      return console.warn("pendle.staticRouter not configured: skipping.");
    }
    if (!dytmWithdrawProcessorAddress) {
      return console.warn("DytmWithdrawProcessor could not be found: skipping.");
    }

    const DytmOfficeAssetGuard = await ethers.getContractFactory("DytmOfficeAssetGuard");

    const args: [number, Address, Address, Address, Address, Address, Address] = [
      addresses.dytm.mismatchDeltaNumerator,
      pendleStaticRouter,
      addresses.dytm.dytmOffice,
      poolFactoryAddress,
      addresses.dytm.dytmPeriphery,
      addresses.dytm.accountSplitterAndMerger,
      dytmWithdrawProcessorAddress,
    ];
    const dytmOfficeAssetGuard = await DytmOfficeAssetGuard.deploy(...args);
    await dytmOfficeAssetGuard.deployed();
    const guardAddress = dytmOfficeAssetGuard.address;

    console.log("DytmOfficeAssetGuard deployed at", guardAddress);
    versions[config.newTag].contracts.DytmOfficeAssetGuard = guardAddress;

    await tryVerify(
      hre,
      guardAddress,
      "contracts/guards/assetGuards/dytm/DytmOfficeAssetGuard.sol:DytmOfficeAssetGuard",
      args,
    );

    const Governance = await hre.artifacts.readArtifact("Governance");
    const assetType = AssetType["Dytm Office Asset"];
    await proposeTx(
      versions[config.oldTag].contracts.Governance,
      new ethers.utils.Interface(Governance.abi).encodeFunctionData("setAssetGuard", [assetType, guardAddress]),
      "setAssetGuard for DytmOfficeAssetGuard",
      config,
      addresses,
    );

    const deployedGuard = {
      assetType,
      guardName: "DytmOfficeAssetGuard",
      guardAddress,
      description: "DYTM Office Asset",
    };

    await addOrReplaceGuardInFile(filenames.assetGuardsFileName, deployedGuard, "assetType");
  }
};
