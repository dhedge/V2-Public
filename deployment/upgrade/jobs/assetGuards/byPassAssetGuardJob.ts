import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx, tryVerify } from "../../../deploymentHelpers";
import { IAddresses, IFileNames, IJob, IUpgradeConfig, IVersions } from "../../../types";
import { AssetType } from "../assetsJob";
import { addOrReplaceGuardInFile } from "../helpers";

export const byPassAssetGuardJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  filenames: IFileNames,
  addresses: IAddresses,
) => {
  console.log("Will deploy ByPassAssetGuard");

  if (config.execute) {
    const ethers = hre.ethers;

    const ByPassAssetGuard = await ethers.getContractFactory("ByPassAssetGuard");
    const byPassAssetGuard = await ByPassAssetGuard.deploy();
    await byPassAssetGuard.deployed();
    const byPassAssetGuardAddress = byPassAssetGuard.address;
    console.log("ByPassAssetGuard deployed at", byPassAssetGuardAddress);

    versions[config.newTag].contracts.ByPassAssetGuard = byPassAssetGuardAddress;

    await tryVerify(
      hre,
      byPassAssetGuardAddress,
      "contracts/guards/assetGuards/ByPassAssetGuard.sol:ByPassAssetGuard",
      [],
    );

    const Governance = await hre.artifacts.readArtifact("Governance");
    const assetHandlerAssetType = AssetType["Deprecated Asset"];
    const setAssetGuardTxData = new ethers.utils.Interface(Governance.abi).encodeFunctionData("setAssetGuard", [
      assetHandlerAssetType,
      byPassAssetGuardAddress,
    ]);

    await proposeTx(
      versions[config.oldTag].contracts.Governance,
      setAssetGuardTxData,
      "setAssetGuard for ByPassAssetGuard",
      config,
      addresses,
    );

    const deployedGuard = {
      assetType: assetHandlerAssetType,
      guardName: "ByPassAssetGuard",
      guardAddress: byPassAssetGuardAddress,
      description: "ByPass Asset Guard",
    };

    await addOrReplaceGuardInFile(filenames.assetGuardsFileName, deployedGuard, "assetType");
  }
};
