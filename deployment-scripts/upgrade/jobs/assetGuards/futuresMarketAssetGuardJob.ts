import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx, tryVerify } from "../../../Helpers";
import { IAddresses, IFileNames, IJob, IUpgradeConfig, IVersions } from "../../../types";
import { AssetType } from "../assetsJob";
import { addOrReplaceGuardInFile } from "../helpers";

export const futuresMarketAssetGuardJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  filenames: IFileNames,
  addresses: IAddresses,
) => {
  console.log("Will deploy futuresmarketassetguard");

  if (config.execute) {
    console.log("Deploying futuresmarketassetguard");
    const ethers = hre.ethers;
    const Governance = await hre.artifacts.readArtifact("Governance");
    const governanceABI = new ethers.utils.Interface(Governance.abi);

    const FuturesMarketAssetGuard = await ethers.getContractFactory("FuturesMarketAssetGuard");
    const futuresMarketAssetGuard = await FuturesMarketAssetGuard.deploy();
    await futuresMarketAssetGuard.deployed();
    await futuresMarketAssetGuard.deployTransaction.wait(5);
    console.log("FuturesMarketAssetGuard deployed at", futuresMarketAssetGuard.address);

    versions[config.newTag].contracts.FuturesMarketAssetGuard = futuresMarketAssetGuard.address;

    await tryVerify(
      hre,
      futuresMarketAssetGuard.address,
      "contracts/guards/assetGuards/FuturesMarketAssetGuard.sol:FuturesMarketAssetGuard",
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
      "setAssetGuard for FuturesMarketAssetGuard",
      config,
      addresses,
    );

    const deployedGuard = {
      assetType: assetHandlerAssetType,
      guardName: "FuturesMarketAssetGuard",
      guardAddress: futuresMarketAssetGuard.address,
      description: "Synthetix Futures Market Asset Guard",
    };

    await addOrReplaceGuardInFile(filenames.assetGuardsFileName, deployedGuard, "assetType");
  }
};
