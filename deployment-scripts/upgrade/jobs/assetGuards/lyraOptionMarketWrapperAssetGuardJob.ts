import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx, tryVerify } from "../../../Helpers";
import { Address, IAddresses, IFileNames, IJob, IUpgradeConfig, IVersions } from "../../../types";
import { addOrReplaceGuardInFile } from "../helpers";

export const lyraOptionMarketWrapperAssetGuardJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  // TODO: This optimally should not be mutated
  versions: IVersions,
  filenames: IFileNames,
  addresses: IAddresses,
) => {
  if (!addresses.lyra?.optionMarketViewer) {
    console.warn("Lyra config missing.. skipping.");
    return;
  }
  if (!addresses.synthetixProxyAddress) {
    console.warn("synthetixProxyAddress missing.. skipping.");
    return;
  }

  const dhedgeOptionMarketWrapperForLyraAddress = versions[config.newTag].contracts.DhedgeOptionMarketWrapperForLyra;
  if (!dhedgeOptionMarketWrapperForLyraAddress) {
    console.warn("DhedgeOptionMarketWrapperForLyra not deployed.. skipping.");
    return;
  }

  const ethers = hre.ethers;
  const Governance = await hre.artifacts.readArtifact("Governance");
  const governanceABI = new ethers.utils.Interface(Governance.abi);

  console.log("Will deploy LyraOptionMarketWrapperAssetGuard");

  const args: [Address] = [dhedgeOptionMarketWrapperForLyraAddress];
  if (config.execute) {
    const AssetGuard = await ethers.getContractFactory("LyraOptionMarketWrapperAssetGuard");
    const assetGuard = await AssetGuard.deploy(...args);
    await assetGuard.deployed();
    console.log("LyraOptionMarketWrapperAssetGuard deployed at", assetGuard.address);
    versions[config.newTag].contracts.LyraOptionMarketWrapperAssetGuard = assetGuard.address;

    await tryVerify(
      hre,
      assetGuard.address,
      "contracts/guards/assetGuards/LyraOptionMarketWrapperAssetGuard.sol:LyraOptionMarketWrapperAssetGuard",
      args,
    );

    const setAssetGuardABI = governanceABI.encodeFunctionData("setAssetGuard", [100, assetGuard.address]);
    await proposeTx(
      versions[config.oldTag].contracts.Governance,
      setAssetGuardABI,
      "setAssetGuard for Asset 100 - lyraOptionMarketWrapperAssetGuard",
      config,
      addresses,
    );

    const deployedGuard = {
      assetType: 100,
      guardName: "LyraOptionMarketWrapperAssetGuard",
      guardAddress: assetGuard.address,
      description: "Lyra OptionMarketWrapper Asset",
    };

    await addOrReplaceGuardInFile(filenames.assetGuardsFileName, deployedGuard, "assetType");
  }
};
