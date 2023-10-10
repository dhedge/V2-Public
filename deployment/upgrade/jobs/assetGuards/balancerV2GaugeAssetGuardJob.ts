import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx, tryVerify } from "../../../deploymentHelpers";
import { IAddresses, IJob, IUpgradeConfig, IVersions, IFileNames } from "../../../types";
import { addOrReplaceGuardInFile } from "../helpers";
import { AssetType } from "../assetsJob";

export const balancerV2GaugeAssetGuardJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  // TODO: This optimally should not be mutated
  versions: IVersions,
  filenames: IFileNames,
  addresses: IAddresses,
) => {
  const ethers = hre.ethers;
  const Governance = await hre.artifacts.readArtifact("Governance");
  const governanceABI = new ethers.utils.Interface(Governance.abi);

  console.log("Will deploy balancerv2gaugeassetguard");
  if (config.execute) {
    const AssetGuard = await ethers.getContractFactory("BalancerV2GaugeAssetGuard");
    const assetGuard = await AssetGuard.deploy();
    await assetGuard.deployed();
    console.log("BalancerV2GaugeAssetGuard deployed at", assetGuard.address);
    versions[config.newTag].contracts.BalancerV2GaugeAssetGuard = assetGuard.address;

    await tryVerify(
      hre,
      assetGuard.address,
      "contracts/guards/assetGuards/BalancerV2GaugeAssetGuard.sol:BalancerV2GaugeAssetGuard",
      [],
    );

    const assetType = AssetType["Balancer V2 Gauge Asset"];
    const setAssetGuardABI = governanceABI.encodeFunctionData("setAssetGuard", [assetType, assetGuard.address]);
    await proposeTx(
      versions[config.oldTag].contracts.Governance,
      setAssetGuardABI,
      `setAssetGuard for Asset ${assetType} - BalancerV2GaugeAssetGuard`,
      config,
      addresses,
    );

    const deployedGuard = {
      assetType,
      guardName: "BalancerV2GaugeAssetGuard",
      guardAddress: assetGuard.address,
      description: "Balancer Staking Gauge Asset",
    };

    await addOrReplaceGuardInFile(filenames.assetGuardsFileName, deployedGuard, "assetType");
  }
};
