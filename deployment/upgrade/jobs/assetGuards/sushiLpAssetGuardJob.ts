import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx, tryVerify } from "../../../deploymentHelpers";
import { IJob, IProposeTxProperties, IUpgradeConfig, IVersions } from "../../../types";
import { addOrReplaceGuardInFile } from "../helpers";

export const sushiLpAssetGuardJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  filenames: { assetGuardsFileName: string },
  addresses: { sushiMiniChefV2Address?: string } & IProposeTxProperties,
) => {
  if (!addresses.sushiMiniChefV2Address) {
    console.warn("sushiMiniChefV2Address not configured for sushiLpAssetGuard: skipping.");
    return;
  }

  console.log("Will deploy sushilpassetguard");
  if (config.execute) {
    const ethers = hre.ethers;
    const Governance = await hre.artifacts.readArtifact("Governance");
    const governanceABI = new ethers.utils.Interface(Governance.abi);

    const SushiLPAssetGuard = await ethers.getContractFactory("SushiLPAssetGuard");
    const sushiLPAssetGuard = await SushiLPAssetGuard.deploy(addresses.sushiMiniChefV2Address); // initialise with Sushi staking pool Id
    await sushiLPAssetGuard.deployed();
    console.log("SushiLPAssetGuard deployed at", sushiLPAssetGuard.address);
    versions[config.newTag].contracts.SushiLPAssetGuard = sushiLPAssetGuard.address;

    await tryVerify(
      hre,
      sushiLPAssetGuard.address,
      "contracts/guards/assetGuards/SushiLPAssetGuard.sol:SushiLPAssetGuard",
      [addresses.sushiMiniChefV2Address],
    );

    await sushiLPAssetGuard.transferOwnership(addresses.protocolDaoAddress);
    const setAssetGuardABI = governanceABI.encodeFunctionData("setAssetGuard", [2, sushiLPAssetGuard.address]);
    await proposeTx(
      versions[config.oldTag].contracts.Governance,
      setAssetGuardABI,
      "setAssetGuard for SushiLPAssetGuard",
      config,
      addresses,
    );

    const deployedGuard = {
      assetType: 2,
      guardName: "SushiLPAssetGuard",
      guardAddress: sushiLPAssetGuard.address,
      description: "Sushi LP tokens",
    };

    await addOrReplaceGuardInFile(filenames.assetGuardsFileName, deployedGuard, "assetType");
  }
};
