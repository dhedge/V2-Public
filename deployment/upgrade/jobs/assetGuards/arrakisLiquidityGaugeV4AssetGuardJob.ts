import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx, tryVerify } from "../../../deploymentHelpers";
import { IAddresses, IJob, IUpgradeConfig, IVersions, IFileNames } from "../../../types";
import { addOrReplaceGuardInFile } from "../helpers";
import { AssetType } from "../assetsJob";

export const arrakisLiquidityGaugeV4AssetGuardJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  filenames: IFileNames,
  addresses: IAddresses,
) => {
  const arrakisV1RouterStakingAddress = addresses.arrakisV1?.arrakisV1RouterStakingAddress;

  if (!arrakisV1RouterStakingAddress) {
    console.warn("Arrakis config missing.. skipping.");
    return;
  }

  const ethers = hre.ethers;
  const Governance = await hre.artifacts.readArtifact("Governance");
  const governanceABI = new ethers.utils.Interface(Governance.abi);

  console.log("Will deploy arrakisliquiditygaugev4assetguard");
  if (config.execute) {
    const AssetGuard = await ethers.getContractFactory("ArrakisLiquidityGaugeV4AssetGuard");
    const assetGuard = await AssetGuard.deploy(arrakisV1RouterStakingAddress);
    await assetGuard.deployed();
    console.log("ArrakisLiquidityGaugeV4AssetGuard deployed at", assetGuard.address);
    versions[config.newTag].contracts.ArrakisLiquidityGaugeV4AssetGuard = assetGuard.address;

    await tryVerify(
      hre,
      assetGuard.address,
      "contracts/guards/assetGuards/ArrakisLiquidityGaugeV4AssetGuard.sol:ArrakisLiquidityGaugeV4AssetGuard",
      [arrakisV1RouterStakingAddress],
    );

    const assetType = AssetType["Arrakis Liquidity Gauge V4 Asset"];
    const setAssetGuardABI = governanceABI.encodeFunctionData("setAssetGuard", [assetType, assetGuard.address]);
    await proposeTx(
      versions[config.oldTag].contracts.Governance,
      setAssetGuardABI,
      "setAssetGuard for Asset 9 - arrakisLiquidityGaugeV4AssetGuard",
      config,
      addresses,
    );

    const deployedGuard = {
      assetType,
      guardName: "ArrakisLiquidityGaugeV4AssetGuard",
      guardAddress: assetGuard.address,
      description: "Arrakis Liquidity Gauge V4",
    };

    await addOrReplaceGuardInFile(filenames.assetGuardsFileName, deployedGuard, "assetType");
  }
};
