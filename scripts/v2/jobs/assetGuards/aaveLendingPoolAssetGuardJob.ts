import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx, tryVerify } from "../../../Helpers";
import { IDeployedAssetGuard, IJob, IUpgradeConfig } from "../types";

export const aaveLendingPoolAssetGuardJob: IJob<IDeployedAssetGuard | undefined> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  // TODO: This should be types and optimally should not be mutated
  versions: any,
  filenames: {},
  addresses: { aaveProtocolDataProviderAddress?: string },
) => {
  if (!addresses.aaveProtocolDataProviderAddress) {
    console.warn("aaveProtocolDataProviderAddress not configured for aaveLendingPoolAssetGuardJob: skipping.");
    return;
  }

  const ethers = hre.ethers;
  const Governance = await hre.artifacts.readArtifact("Governance");
  const governanceABI = new ethers.utils.Interface(Governance.abi);

  console.log("Will deploy aavelendingpoolassetguard");
  if (config.execute) {
    if (!addresses.aaveProtocolDataProviderAddress) {
      throw new Error("No aaveProtocolDataProviderAddress configured");
    }

    const AaveLendingPoolAssetGuard = await ethers.getContractFactory("AaveLendingPoolAssetGuard");
    const aaveLendingPoolAssetGuard = await AaveLendingPoolAssetGuard.deploy(addresses.aaveProtocolDataProviderAddress);
    await aaveLendingPoolAssetGuard.deployed();
    console.log("AaveLendingPoolAssetGuard deployed at", aaveLendingPoolAssetGuard.address);
    versions[config.newTag].contracts.AaveLendingPoolAssetGuard = aaveLendingPoolAssetGuard.address;

    await tryVerify(
      hre,
      aaveLendingPoolAssetGuard.address,
      "contracts/guards/assetGuards/AaveLendingPoolAssetGuard.sol:AaveLendingPoolAssetGuard",
      [addresses.aaveProtocolDataProviderAddress],
    );

    const setAssetGuardABI = governanceABI.encodeFunctionData("setAssetGuard", [3, aaveLendingPoolAssetGuard.address]);
    await proposeTx(
      versions[config.oldTag].contracts.Governance,
      setAssetGuardABI,
      "setAssetGuard for aaveLendingPoolAssetGuard",
      config.execute,
      config.restartnonce,
    );

    return {
      AssetType: 3,
      GuardName: "AaveLendingPoolAssetGuard",
      GuardAddress: aaveLendingPoolAssetGuard.address,
      Description: "Aave Lending Pool",
    };
  }
};
