import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx, tryVerify } from "../../../deploymentHelpers";
import { IAddresses, IFileNames, IJob, IUpgradeConfig, IVersions } from "../../../types";
import { AssetType } from "../assetsJob";
import { addOrReplaceGuardInFile } from "../helpers";

export const synthetixPerpsV2MarketAssetGuardJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  filenames: IFileNames,
  addresses: IAddresses,
) => {
  console.log("Will deploy perpsv2marketassetguard");
  if (!addresses.assets.susd) {
    console.warn("sUSD address not configured for perpsv2MarketAssetGuardJob: skipping.");
    return;
  }
  if (!addresses.perpsV2) {
    console.warn("config not configured for perpsv2MarketAssetGuardJob: skipping.");
    return;
  }

  if (config.execute) {
    console.log("Deploying perpsv2marketassetguard");
    const ethers = hre.ethers;
    const Governance = await hre.artifacts.readArtifact("Governance");
    const governanceABI = new ethers.utils.Interface(Governance.abi);

    const SynthetixPerpsV2MarketAssetGuard = await ethers.getContractFactory("SynthetixPerpsV2MarketAssetGuard");
    const args: Parameters<typeof SynthetixPerpsV2MarketAssetGuard.deploy> = [
      addresses.perpsV2.addressResolver,
      addresses.assets.susd,
      addresses.perpsV2.withdrawSlippageSettings,
    ];
    const perpsv2MarketAssetGuard = await SynthetixPerpsV2MarketAssetGuard.deploy(...args);
    await perpsv2MarketAssetGuard.deployed();

    console.log("SynthetixPerpsV2MarketAssetGuard deployed at", perpsv2MarketAssetGuard.address);

    versions[config.newTag].contracts.SynthetixPerpsV2MarketAssetGuard = perpsv2MarketAssetGuard.address;

    await tryVerify(
      hre,
      perpsv2MarketAssetGuard.address,
      "contracts/guards/assetGuards/SynthetixPerpsV2MarketAssetGuard.sol:SynthetixPerpsV2MarketAssetGuard",
      args,
    );
    const assetHandlerAssetType = AssetType["Synthetix PerpsV2 Market Asset"];
    const setAssetGuardABI = governanceABI.encodeFunctionData("setAssetGuard", [
      assetHandlerAssetType,
      perpsv2MarketAssetGuard.address,
    ]);

    await proposeTx(
      versions[config.oldTag].contracts.Governance,
      setAssetGuardABI,
      "setAssetGuard for SynthetixPerpsV2MarketAssetGuard",
      config,
      addresses,
    );

    const deployedGuard = {
      assetType: assetHandlerAssetType,
      guardName: "SynthetixPerpsV2MarketAssetGuard",
      guardAddress: perpsv2MarketAssetGuard.address,
      description: "Synthetix PerpsV2 Market Asset Guard",
    };

    await addOrReplaceGuardInFile(filenames.assetGuardsFileName, deployedGuard, "assetType");
  }
};
