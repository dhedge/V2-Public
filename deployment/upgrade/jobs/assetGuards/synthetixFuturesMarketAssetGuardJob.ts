import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx, tryVerify } from "../../../deploymentHelpers";
import { IAddresses, IFileNames, IJob, IUpgradeConfig, IVersions } from "../../../types";
import { AssetType } from "../assetsJob";
import { addOrReplaceGuardInFile } from "../helpers";

export const synthetixFuturesMarketAssetGuardJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  filenames: IFileNames,
  addresses: IAddresses,
) => {
  console.log("Will deploy synthetixFuturesMarketAssetGuardJob");

  if (config.execute) {
    console.log("Deploying synthetixFuturesMarketAssetGuardJob");
    const ethers = hre.ethers;
    const Governance = await hre.artifacts.readArtifact("Governance");
    const governanceABI = new ethers.utils.Interface(Governance.abi);

    const SynthetixFuturesMarketAssetGuard = await ethers.getContractFactory("SynthetixFuturesMarketAssetGuard");
    const futuresMarketAssetGuard = await SynthetixFuturesMarketAssetGuard.deploy();
    await futuresMarketAssetGuard.deployed();
    await futuresMarketAssetGuard.deployTransaction.wait(5);
    console.log("SynthetixFuturesMarketAssetGuard deployed at", futuresMarketAssetGuard.address);

    versions[config.newTag].contracts.SynthetixFuturesMarketAssetGuard = futuresMarketAssetGuard.address;

    await tryVerify(
      hre,
      futuresMarketAssetGuard.address,
      "contracts/guards/assetGuards/SynthetixFuturesMarketAssetGuard.sol:SynthetixFuturesMarketAssetGuard",
      [],
    );
    const assetHandlerAssetType = AssetType["Synthetix Futures Market Asset"];
    const setAssetGuardABI = governanceABI.encodeFunctionData("setAssetGuard", [
      assetHandlerAssetType,
      futuresMarketAssetGuard.address,
    ]);

    await proposeTx(
      versions[config.oldTag].contracts.Governance,
      setAssetGuardABI,
      "setAssetGuard for SynthetixFuturesMarketAssetGuard",
      config,
      addresses,
    );

    const deployedGuard = {
      assetType: assetHandlerAssetType,
      guardName: "SynthetixFuturesMarketAssetGuard",
      guardAddress: futuresMarketAssetGuard.address,
      description: "Synthetix Futures Market Asset Guard",
    };

    await addOrReplaceGuardInFile(filenames.assetGuardsFileName, deployedGuard, "assetType");
  }
};
