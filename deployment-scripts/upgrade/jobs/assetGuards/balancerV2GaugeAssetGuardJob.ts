import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx, tryVerify } from "../../../Helpers";
import { IAddresses, IJob, IUpgradeConfig, IVersions } from "../../../types";
import { addOrReplaceGuardInFile } from "../helpers";

export const balancerV2GaugeAssetGuardJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  // TODO: This optimally should not be mutated
  versions: IVersions,
  filenames: { assetGuardsFileName: string },
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

    const setAssetGuardABI = governanceABI.encodeFunctionData("setAssetGuard", [10, assetGuard.address]);
    await proposeTx(
      versions[config.oldTag].contracts.Governance,
      setAssetGuardABI,
      "setAssetGuard for Asset 10 - BalancerV2GaugeAssetGuard",
      config,
      addresses,
    );

    const deployedGuard = {
      assetType: 10,
      guardName: "BalancerV2GaugeAssetGuard",
      guardAddress: assetGuard.address,
      description: "Balancer Staking Gauge Asset",
    };

    await addOrReplaceGuardInFile(filenames.assetGuardsFileName, deployedGuard, "assetType");
  }
};
