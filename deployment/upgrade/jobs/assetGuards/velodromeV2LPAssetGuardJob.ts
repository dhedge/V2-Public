import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx, tryVerify } from "../../../deploymentHelpers";
import { IAddresses, IFileNames, IJob, IUpgradeConfig, IVersions } from "../../../types";
import { AssetType } from "../assetsJob";
import { addOrReplaceGuardInFile } from "../helpers";

export const velodromeV2LPAssetGuardJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  filenames: IFileNames,
  addresses: IAddresses,
) => {
  const velodromeV2VoterAddress = addresses.velodrome?.voterV2;

  if (!velodromeV2VoterAddress) {
    return console.warn("Velodrome V2 Voter address not configured for VelodromeV2LPAssetGuard. Skipping.");
  }

  console.log("Will deploy VelodromeV2LPAssetGuard");

  if (config.execute) {
    const ethers = hre.ethers;
    const Governance = await hre.artifacts.readArtifact("Governance");
    const governanceABI = new ethers.utils.Interface(Governance.abi);

    const VelodromeV2LPAssetGuard = await ethers.getContractFactory("VelodromeV2LPAssetGuard");
    const velodromeV2LPAssetGuard = await VelodromeV2LPAssetGuard.deploy(velodromeV2VoterAddress);
    await velodromeV2LPAssetGuard.deployed();
    const address = velodromeV2LPAssetGuard.address;

    console.log("VelodromeV2LPAssetGuard deployed at", address);

    await tryVerify(
      hre,
      address,
      "contracts/guards/assetGuards/velodrome/VelodromeV2LPAssetGuard.sol:VelodromeV2LPAssetGuard",
      [velodromeV2VoterAddress],
    );

    versions[config.newTag].contracts.VelodromeV2LPAssetGuard = address;

    const assetHandlerAssetType = AssetType["Velodrome V2 LP/Gauge Asset"];
    const setAssetGuardABI = governanceABI.encodeFunctionData("setAssetGuard", [assetHandlerAssetType, address]);

    await proposeTx(
      versions[config.oldTag].contracts.Governance,
      setAssetGuardABI,
      "setAssetGuard for VelodromeV2LPAssetGuard",
      config,
      addresses,
    );

    const deployedGuard = {
      assetType: assetHandlerAssetType,
      guardName: "VelodromeV2LPAssetGuard",
      guardAddress: address,
      description: "Velodrome V2 LP + Gauge Positions",
    };

    await addOrReplaceGuardInFile(filenames.assetGuardsFileName, deployedGuard, "assetType");
  }
};
