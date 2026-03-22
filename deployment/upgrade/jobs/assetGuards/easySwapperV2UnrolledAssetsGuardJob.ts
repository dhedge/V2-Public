import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx, tryVerify } from "../../../deploymentHelpers";
import { IAddresses, IFileNames, IJob, IUpgradeConfig, IVersions } from "../../../types";
import { AssetType } from "../assetsJob";
import { addOrReplaceGuardInFile } from "../helpers";

export const easySwapperV2UnrolledAssetsGuardJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  filenames: IFileNames,
  addresses: IAddresses,
) => {
  console.log("Will deploy EasySwapperV2UnrolledAssetsGuard");

  const poolLimitOrderManagerProxy = versions[config.newTag].contracts.PoolLimitOrderManagerProxy;
  if (!poolLimitOrderManagerProxy) return console.warn("PoolLimitOrderManagerProxy could not be found: skipping.");

  if (config.execute) {
    const ethers = hre.ethers;

    const EasySwapperV2UnrolledAssetsGuard = await ethers.getContractFactory("EasySwapperV2UnrolledAssetsGuard");
    const args: Parameters<typeof EasySwapperV2UnrolledAssetsGuard.deploy> = [poolLimitOrderManagerProxy];
    const easySwapperV2UnrolledAssetsGuard = await EasySwapperV2UnrolledAssetsGuard.deploy(...args);
    await easySwapperV2UnrolledAssetsGuard.deployed();
    const easySwapperV2UnrolledAssetsGuardAddress = easySwapperV2UnrolledAssetsGuard.address;
    console.log("EasySwapperV2UnrolledAssetsGuard deployed at", easySwapperV2UnrolledAssetsGuardAddress);

    versions[config.newTag].contracts.EasySwapperV2UnrolledAssetsGuard = easySwapperV2UnrolledAssetsGuardAddress;

    await tryVerify(
      hre,
      easySwapperV2UnrolledAssetsGuardAddress,
      "contracts/guards/assetGuards/EasySwapperV2UnrolledAssetsGuard.sol:EasySwapperV2UnrolledAssetsGuard",
      args,
    );

    const Governance = await hre.artifacts.readArtifact("Governance");
    const assetType = AssetType["EasySwapperV2 Unrolled Assets"];
    const setAssetGuardTxData = new ethers.utils.Interface(Governance.abi).encodeFunctionData("setAssetGuard", [
      assetType,
      easySwapperV2UnrolledAssetsGuardAddress,
    ]);

    await proposeTx(
      versions[config.oldTag].contracts.Governance,
      setAssetGuardTxData,
      "setAssetGuard for EasySwapperV2UnrolledAssetsGuard",
      config,
      addresses,
    );

    const deployedGuard = {
      assetType,
      guardName: "EasySwapperV2UnrolledAssetsGuard",
      guardAddress: easySwapperV2UnrolledAssetsGuardAddress,
      description: "EasySwapperV2 Unrolled Assets Guard",
    };

    await addOrReplaceGuardInFile(filenames.assetGuardsFileName, deployedGuard, "assetType");
  }
};
