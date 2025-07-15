import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx, tryVerify } from "../../../deploymentHelpers";
import { IJob, IAddresses, IUpgradeConfig, IVersions, IFileNames } from "../../../types";
import { addOrReplaceGuardInFile } from "../helpers";
import { AssetType } from "../assetsJob";

export const pendlePTAssetGuardJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  filenames: IFileNames,
  addresses: IAddresses,
) => {
  console.log("Will deploy PendlePTAssetGuard");

  if (!addresses.pendle) return console.log("Pendle addresses not provided in deployment config");

  if (config.execute) {
    const ethers = hre.ethers;
    const Governance = await hre.artifacts.readArtifact("Governance");

    const PendlePTAssetGuard = await ethers.getContractFactory("PendlePTAssetGuard");
    const args: Parameters<typeof PendlePTAssetGuard.deploy> = [
      addresses.pendle.marketFactoryV3,
      addresses.pendle.knownMarkets,
    ];
    const pendlePTAssetGuard = await PendlePTAssetGuard.deploy(...args);
    await pendlePTAssetGuard.deployed();
    const guardAddress = pendlePTAssetGuard.address;
    console.log("PendlePTAssetGuard deployed at", guardAddress);

    versions[config.newTag].contracts.PendlePTAssetGuard = guardAddress;

    await tryVerify(
      hre,
      guardAddress,
      "contracts/guards/assetGuards/pendle/PendlePTAssetGuard.sol:PendlePTAssetGuard",
      args,
    );

    const assetType = AssetType["Pendle Principal Token"];
    await proposeTx(
      versions[config.oldTag].contracts.Governance,
      new ethers.utils.Interface(Governance.abi).encodeFunctionData("setAssetGuard", [assetType, guardAddress]),
      "setAssetGuard for PendlePTAssetGuard",
      config,
      addresses,
    );

    const deployedGuard = {
      assetType,
      guardName: "PendlePTAssetGuard",
      guardAddress,
      description: "Pendle Principal Token",
    };

    await addOrReplaceGuardInFile(filenames.assetGuardsFileName, deployedGuard, "assetType");
  }
};
