import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx, tryVerify } from "../../../deploymentHelpers";
import { IAddresses, IJob, IUpgradeConfig, IVersions, IFileNames } from "../../../types";
import { addOrReplaceGuardInFile } from "../helpers";

export const aaveV3LendingPoolAssetGuardJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  // TODO: This optimally should not be mutated
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
    const aaveLendingPoolAssetGuard = await AaveLendingPoolAssetGuard.deploy(
      addresses.aaveV3.aaveProtocolDataProviderAddress,
      addresses.aaveV3.aaveLendingPoolAddress,
    );
    await aaveLendingPoolAssetGuard.deployed();
    console.log("AaveLendingPoolAssetGuard deployed at", aaveLendingPoolAssetGuard.address);
    versions[config.newTag].contracts.AaveLendingPoolAssetGuardV3 = aaveLendingPoolAssetGuard.address;

    await tryVerify(
      hre,
      aaveLendingPoolAssetGuard.address,
      "contracts/guards/assetGuards/AaveLendingPoolAssetGuard.sol:AaveLendingPoolAssetGuard",
      [addresses.aaveV3.aaveProtocolDataProviderAddress, addresses.aaveV3.aaveLendingPoolAddress],
    );

    const setAssetGuardABI = governanceABI.encodeFunctionData("setAssetGuard", [8, aaveLendingPoolAssetGuard.address]);
    await proposeTx(
      versions[config.oldTag].contracts.Governance,
      setAssetGuardABI,
      "setAssetGuard for Asset 8 - aaveLendingPoolAssetGuard",
      config,
      addresses,
    );

    const deployedGuard = {
      assetType: 8,
      guardName: "AaveLendingPoolAssetGuard",
      guardAddress: aaveLendingPoolAssetGuard.address,
      description: "Aave V3 Lending Pool",
    };

    await addOrReplaceGuardInFile(filenames.assetGuardsFileName, deployedGuard, "assetType");
  }
};
