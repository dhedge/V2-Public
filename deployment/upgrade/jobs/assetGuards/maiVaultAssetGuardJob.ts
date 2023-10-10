import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx, tryVerify } from "../../../deploymentHelpers";
import { Address, IAddresses, IFileNames, IJob, IUpgradeConfig, IVersions } from "../../../types";
import { AssetType } from "../assetsJob";
import { addOrReplaceGuardInFile } from "../helpers";

export const maiVaultAssetGuardJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  filenames: IFileNames,
  addresses: IAddresses,
) => {
  console.log("Will deploy maivaultassetguard");
  if (!addresses.assets?.usdc) {
    console.warn("usdc address not configured for MaiVaultAssetGuard skipping.");
    return;
  }
  if (!addresses.aaveV3?.aaveLendingPoolAddress) {
    console.warn("aaveLendingPoolAddress address not configured for MaiVaultAssetGuard skipping.");
    return;
  }
  if (config.execute) {
    const ethers = hre.ethers;
    const Governance = await hre.artifacts.readArtifact("Governance");
    const governanceABI = new ethers.utils.Interface(Governance.abi);

    const args: [Address, Address] = [addresses.assets?.usdc, addresses.aaveV3?.aaveLendingPoolAddress];
    const MaiVaultAssetGuard = await ethers.getContractFactory("MaiVaultAssetGuard");
    const maiVaultAssetGuard = await MaiVaultAssetGuard.deploy(...args);
    await maiVaultAssetGuard.deployed();
    console.log("MaiVaultAssetGuard deployed at", maiVaultAssetGuard.address);

    versions[config.newTag].contracts.MaiVaultAssetGuard = maiVaultAssetGuard.address;

    await tryVerify(
      hre,
      maiVaultAssetGuard.address,
      "contracts/guards/assetGuards/MaiVaultAssetGuard.sol:MaiVaultAssetGuard",
      args,
    );
    const assetHandlerAssetType = AssetType["Mai Vault Asset"];
    const setAssetGuardABI = governanceABI.encodeFunctionData("setAssetGuard", [
      assetHandlerAssetType,
      maiVaultAssetGuard.address,
    ]);

    await proposeTx(
      versions[config.oldTag].contracts.Governance,
      setAssetGuardABI,
      "setAssetGuard for MaiVaultAssetGuard",
      config,
      addresses,
    );

    const deployedGuard = {
      assetType: assetHandlerAssetType,
      guardName: "MaiVaultAssetGuard",
      guardAddress: maiVaultAssetGuard.address,
      description: "Mai Vault Asset Guard",
    };

    await addOrReplaceGuardInFile(filenames.assetGuardsFileName, deployedGuard, "assetType");
  }
};
