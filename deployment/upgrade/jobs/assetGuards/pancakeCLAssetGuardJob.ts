import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx, tryVerify } from "../../../deploymentHelpers";
import { IJob, IUpgradeConfig, IVersions, IFileNames, IAddresses } from "../../../types";
import { addOrReplaceGuardInFile } from "../helpers";
import { AssetType } from "../assetsJob";

export const pancakeCLAssetGuardJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  filenames: IFileNames,
  addresses: IAddresses,
) => {
  const masterChefV3 = addresses.pancakeswap?.masterChefV3;

  if (!masterChefV3) {
    return console.warn("Pancakeswap MasterChefV3 address not configured for PancakeCLAssetGuard. skipping.");
  }

  console.log("Will deploy PancakeCLAssetGuard");

  if (config.execute) {
    const ethers = hre.ethers;

    const PancakeCLAssetGuard = await ethers.getContractFactory("PancakeCLAssetGuard");
    const pancakeCLAssetGuard = await PancakeCLAssetGuard.deploy(masterChefV3);
    await pancakeCLAssetGuard.deployed();
    const pancakeCLAssetGuardAddress = pancakeCLAssetGuard.address;
    console.log("PancakeCLAssetGuard deployed at", pancakeCLAssetGuardAddress);

    versions[config.newTag].contracts.PancakeCLAssetGuard = pancakeCLAssetGuardAddress;

    await tryVerify(
      hre,
      pancakeCLAssetGuardAddress,
      "contracts/guards/assetGuards/pancake/PancakeCLAssetGuard.sol:PancakeCLAssetGuard",
      [masterChefV3],
    );

    const assetHandlerAssetType = AssetType["Pancake CL NFT Position Asset"];
    const Governance = await hre.artifacts.readArtifact("Governance");
    const setAssetGuardABI = new ethers.utils.Interface(Governance.abi).encodeFunctionData("setAssetGuard", [
      assetHandlerAssetType,
      pancakeCLAssetGuardAddress,
    ]);

    await proposeTx(
      versions[config.oldTag].contracts.Governance,
      setAssetGuardABI,
      "setAssetGuard for PancakeCLAssetGuard",
      config,
      addresses,
    );

    const deployedGuard = {
      assetType: assetHandlerAssetType,
      guardName: "PancakeCLAssetGuard",
      guardAddress: pancakeCLAssetGuardAddress,
      description: "PancakeSwap Concentrated Liquidity positions",
    };

    await addOrReplaceGuardInFile(filenames.assetGuardsFileName, deployedGuard, "assetType");
  }
};
