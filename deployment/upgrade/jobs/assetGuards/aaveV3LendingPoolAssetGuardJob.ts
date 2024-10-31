import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx, tryVerify } from "../../../deploymentHelpers";
import { IAddresses, IJob, IUpgradeConfig, IVersions, IFileNames } from "../../../types";
import { addOrReplaceGuardInFile } from "../helpers";
import { AssetType } from "../assetsJob";

export const aaveV3LendingPoolAssetGuardJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  filenames: IFileNames,
  addresses: IAddresses,
) => {
  if (!addresses.aaveV3) {
    console.warn("aaveV3 config missing.. skipping.");
    return;
  }

  const ethers = hre.ethers;
  const Governance = await hre.artifacts.readArtifact("Governance");
  const governanceABI = new ethers.utils.Interface(Governance.abi);

  console.log("Will deploy aavelendingpoolassetguard");
  if (config.execute) {
    const AaveLendingPoolAssetGuard = await ethers.getContractFactory("AaveLendingPoolAssetGuard");
    const args: [string, string] = [
      addresses.aaveV3.aaveProtocolDataProviderAddress,
      addresses.aaveV3.aaveLendingPoolAddress,
    ];
    const aaveLendingPoolAssetGuard = await AaveLendingPoolAssetGuard.deploy(...args);

    await aaveLendingPoolAssetGuard.deployed();
    console.log("AaveLendingPoolAssetGuard deployed at", aaveLendingPoolAssetGuard.address);
    versions[config.newTag].contracts.AaveLendingPoolAssetGuardV3 = aaveLendingPoolAssetGuard.address;

    await tryVerify(
      hre,
      aaveLendingPoolAssetGuard.address,
      "contracts/guards/assetGuards/AaveLendingPoolAssetGuard.sol:AaveLendingPoolAssetGuard",
      args,
    );

    const assetType = AssetType["Aave V3 Lending Pool Asset"];
    const setAssetGuardABI = governanceABI.encodeFunctionData("setAssetGuard", [
      assetType,
      aaveLendingPoolAssetGuard.address,
    ]);
    await proposeTx(
      versions[config.oldTag].contracts.Governance,
      setAssetGuardABI,
      `setAssetGuard for AssetType ${assetType} - aaveLendingPoolAssetGuard`,
      config,
      addresses,
    );

    const deployedGuard = {
      assetType,
      guardName: "AaveLendingPoolAssetGuard",
      guardAddress: aaveLendingPoolAssetGuard.address,
      description: "Aave V3 Lending Pool",
    };

    await addOrReplaceGuardInFile(filenames.assetGuardsFileName, deployedGuard, "assetType");
  }
};
