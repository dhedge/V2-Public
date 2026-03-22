import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx, tryVerify } from "../../../deploymentHelpers";
import { Address, IAddresses, IFileNames, IJob, IUpgradeConfig, IVersions } from "../../../types";
import { AssetType } from "../assetsJob";
import { addOrReplaceGuardInFile } from "../helpers";

export const gmxPerpMarketAssetGuardJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  filenames: IFileNames,
  addresses: IAddresses,
) => {
  console.log("Will deploy GmxPerpMarketAssetGuard");
  const gmxExchangeRouterAddress = addresses.gmx?.exchangeRouter;

  if (!gmxExchangeRouterAddress) {
    return console.warn("No config for GmxPerpMarketAssetGuard: skipping.");
  }

  if (config.execute) {
    const ethers = hre.ethers;
    const Governance = await hre.artifacts.readArtifact("Governance");
    const governanceABI = new ethers.utils.Interface(Governance.abi);

    const GmxHelperLib = await ethers.getContractFactory("GmxHelperLib");
    const gmxHelperLib = await GmxHelperLib.deploy();
    await gmxHelperLib.deployed();
    console.log("GmxHelperLib deployed at:", gmxHelperLib.address);
    versions[config.newTag].contracts.GmxHelperLib = gmxHelperLib.address;

    await tryVerify(hre, gmxHelperLib.address, "contracts/utils/gmx/GmxHelperLib.sol:GmxHelperLib", []);

    const GmxClaimableCollateralTrackerLib = await ethers.getContractFactory("GmxClaimableCollateralTrackerLib", {
      libraries: {
        GmxHelperLib: gmxHelperLib.address,
      },
    });
    const gmxClaimableCollateralTrackerLib = await GmxClaimableCollateralTrackerLib.deploy();
    await gmxClaimableCollateralTrackerLib.deployed();
    const gmxClaimableCollateralTrackerLibAddress = gmxClaimableCollateralTrackerLib.address;

    await tryVerify(
      hre,
      gmxClaimableCollateralTrackerLibAddress,
      "contracts/utils/gmx/GmxClaimableCollateralTrackerLib.sol:GmxClaimableCollateralTrackerLib",
      [],
    );
    versions[config.newTag].contracts.GmxClaimableCollateralTrackerLib = gmxClaimableCollateralTrackerLibAddress;

    const GmxPerpMarketAssetGuard = await ethers.getContractFactory("GmxPerpMarketAssetGuard", {
      libraries: {
        GmxClaimableCollateralTrackerLib: gmxClaimableCollateralTrackerLibAddress,
        GmxHelperLib: gmxHelperLib.address,
      },
    });

    const args: [Address] = [gmxExchangeRouterAddress];
    const gmxPerpMarketAssetGuard = await GmxPerpMarketAssetGuard.deploy(...args);
    await gmxPerpMarketAssetGuard.deployed();

    console.log("GmxPerpMarketAssetGuard deployed at", gmxPerpMarketAssetGuard.address);

    versions[config.newTag].contracts.GmxPerpMarketAssetGuard = gmxPerpMarketAssetGuard.address;

    await tryVerify(
      hre,
      gmxPerpMarketAssetGuard.address,
      "contracts/guards/assetGuards/gmx/GmxPerpMarketAssetGuard.sol:GmxPerpMarketAssetGuard",
      args,
    );
    const assetHandlerAssetType = AssetType["Gmx Perps Market Asset"];
    const setAssetGuardABI = governanceABI.encodeFunctionData("setAssetGuard", [
      assetHandlerAssetType,
      gmxPerpMarketAssetGuard.address,
    ]);

    await proposeTx(
      versions[config.oldTag].contracts.Governance,
      setAssetGuardABI,
      "setAssetGuard for GmxPerpMarketAssetGuard",
      config,
      addresses,
    );

    const deployedGuard = {
      assetType: assetHandlerAssetType,
      guardName: "GmxPerpMarketAssetGuard",
      guardAddress: gmxPerpMarketAssetGuard.address,
      description: "Gmx Perps Market Asset Guard",
    };

    await addOrReplaceGuardInFile(filenames.assetGuardsFileName, deployedGuard, "assetType");
  }
};
