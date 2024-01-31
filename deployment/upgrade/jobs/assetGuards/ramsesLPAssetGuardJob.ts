import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx, tryVerify } from "../../../deploymentHelpers";
import { IAddresses, IFileNames, IJob, IUpgradeConfig, IVersions } from "../../../types";
import { AssetType } from "../assetsJob";
import { addOrReplaceGuardInFile } from "../helpers";

export const ramsesLPAssetGuardJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  filenames: IFileNames,
  addresses: IAddresses,
) => {
  console.log("Will deploy RamsesLPAssetGuard");
  const ramsesVoter = addresses.ramses?.voter;

  if (!ramsesVoter) {
    return console.warn("RAMSES voter address not configured for RamsesLPAssetGuard. skipping.");
  }

  if (config.execute) {
    const ethers = hre.ethers;

    const RamsesLPAssetGuard = await ethers.getContractFactory("RamsesLPAssetGuard");
    const ramsesLPAssetGuard = await RamsesLPAssetGuard.deploy(ramsesVoter);
    await ramsesLPAssetGuard.deployed();
    const ramsesLPAssetGuardAddress = ramsesLPAssetGuard.address;
    console.log("RamsesLPAssetGuard deployed at", ramsesLPAssetGuardAddress);

    versions[config.newTag].contracts.RamsesLPAssetGuard = ramsesLPAssetGuardAddress;

    await tryVerify(
      hre,
      ramsesLPAssetGuardAddress,
      "contracts/guards/assetGuards/RamsesLPAssetGuard.sol:RamsesLPAssetGuard",
      [ramsesVoter],
    );

    const Governance = await hre.artifacts.readArtifact("Governance");
    const governanceABI = new ethers.utils.Interface(Governance.abi);
    const assetHandlerAssetType = AssetType["Ramses LP/Gauge Asset"];
    const setAssetGuardTxData = governanceABI.encodeFunctionData("setAssetGuard", [
      assetHandlerAssetType,
      ramsesLPAssetGuardAddress,
    ]);

    await proposeTx(
      versions[config.oldTag].contracts.Governance,
      setAssetGuardTxData,
      "setAssetGuard for RamsesLPAssetGuard",
      config,
      addresses,
    );

    const deployedGuard = {
      assetType: assetHandlerAssetType,
      guardName: "RamsesLPAssetGuard",
      guardAddress: ramsesLPAssetGuardAddress,
      description: "Ramses LP + Gauge Positions",
    };

    await addOrReplaceGuardInFile(filenames.assetGuardsFileName, deployedGuard, "assetType");
  }
};
