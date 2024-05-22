import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx, tryVerify } from "../../../deploymentHelpers";
import { IJob, IProposeTxProperties, IUpgradeConfig, IVersions } from "../../../types";
import { addOrReplaceGuardInFile } from "../helpers";
import { AssetType } from "../assetsJob";

export const lendingEnabledAssetGuardJobGenerator = (
  assetType: (typeof AssetType)["Lending Enable Asset"] | (typeof AssetType)["Synthetix + LendingEnabled"],
): IJob<void> => {
  return async (
    config: IUpgradeConfig,
    hre: HardhatRuntimeEnvironment,
    // TODO: This optimally should not be mutated
    versions: IVersions,
    filenames: { assetGuardsFileName: string },
    addresses: IProposeTxProperties,
  ) => {
    console.log("Will deploy lendingenabledassetguard");
    if (config.execute) {
      const LendingEnabledAssetGuard = await hre.ethers.getContractFactory("LendingEnabledAssetGuard");
      const lendingEnabledAssetGuard = await LendingEnabledAssetGuard.deploy();
      await lendingEnabledAssetGuard.deployed();
      console.log("LendingEnabledAssetGuard deployed at", lendingEnabledAssetGuard.address);

      const guardName =
        assetType === (typeof AssetType)["Lending Enable Asset"]
          ? "LendingEnabledAssetGuard"
          : "SynthetixLendingEnabledAssetGuard";
      versions[config.newTag].contracts[guardName] = lendingEnabledAssetGuard.address;

      await tryVerify(
        hre,
        lendingEnabledAssetGuard.address,
        "contracts/guards/assetGuards/LendingEnabledAssetGuard.sol:LendingEnabledAssetGuard",
        [],
      );

      const Governance = await hre.artifacts.readArtifact("Governance");
      const governanceABI = new hre.ethers.utils.Interface(Governance.abi);

      const setAssetGuardABI = governanceABI.encodeFunctionData("setAssetGuard", [
        assetType,
        lendingEnabledAssetGuard.address,
      ]);
      await proposeTx(
        versions[config.oldTag].contracts.Governance,
        setAssetGuardABI,
        "setAssetGuard for LendingEnabledAssetGuard",
        config,
        addresses,
      );
      const deployedGuard = {
        assetType,
        guardName,
        guardAddress: lendingEnabledAssetGuard.address,
        description: "Lending Enabled Asset tokens",
      };
      await addOrReplaceGuardInFile(filenames.assetGuardsFileName, deployedGuard, "assetType");
    }
  };
};
