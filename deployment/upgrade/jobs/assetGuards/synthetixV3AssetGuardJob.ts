import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx, tryVerify } from "../../../deploymentHelpers";
import { Address, IAddresses, IFileNames, IJob, IUpgradeConfig, IVersions } from "../../../types";
import { AssetType } from "../assetsJob";
import { addOrReplaceGuardInFile } from "../helpers";

export const synthetixV3AssetGuardJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  filenames: IFileNames,
  addresses: IAddresses,
) => {
  console.log("Will deploy SynthetixV3AssetGuard");
  const synthetixV3SpotMarketAddress = addresses.synthetixV3?.spotMarket;

  if (!synthetixV3SpotMarketAddress) {
    return console.warn("No SpotMarket address for SynthetixV3AssetGuard: skipping.");
  }

  if (config.execute) {
    const ethers = hre.ethers;
    const Governance = await hre.artifacts.readArtifact("Governance");
    const governanceABI = new ethers.utils.Interface(Governance.abi);

    const SynthetixV3AssetGuard = await ethers.getContractFactory("SynthetixV3AssetGuard");
    const args: [Address] = [synthetixV3SpotMarketAddress];
    const synthetixV3AssetGuard = await SynthetixV3AssetGuard.deploy(...args);
    await synthetixV3AssetGuard.deployed();
    const synthetixV3AssetGuardAddress = synthetixV3AssetGuard.address;
    console.log("SynthetixV3AssetGuard deployed at", synthetixV3AssetGuardAddress);
    versions[config.newTag].contracts.SynthetixV3AssetGuard = synthetixV3AssetGuardAddress;

    await tryVerify(
      hre,
      synthetixV3AssetGuardAddress,
      "contracts/guards/assetGuards/synthetixV3/SynthetixV3AssetGuard.sol:SynthetixV3AssetGuard",
      args,
    );

    const assetHandlerAssetType = AssetType["Synthetix V3 Position Asset"];

    await proposeTx(
      versions[config.oldTag].contracts.Governance,
      governanceABI.encodeFunctionData("setAssetGuard", [assetHandlerAssetType, synthetixV3AssetGuardAddress]),
      "setAssetGuard for SynthetixV3AssetGuard",
      config,
      addresses,
    );

    await addOrReplaceGuardInFile(
      filenames.assetGuardsFileName,
      {
        assetType: assetHandlerAssetType,
        guardName: "SynthetixV3AssetGuard",
        guardAddress: synthetixV3AssetGuardAddress,
        description: "Synthetix V3 Position Asset",
      },
      "assetType",
    );

    /*
     * This is to update SynthetixV3AssetGuard storage with fresh debt records for whitelisted vaults after guard re-deploy
     * Calling mintManagerFee on vault's PoolLogic will update its Synthetix debt records
     * There is no necessity to call mintManagerFee from a multisig, can be called from any account
     * However for the sake of automation and ready-to-use deployment infrastructure, we will call it from the multisig
     */
    if (!addresses.synthetixV3?.dHedgeVaultsWhitelist || addresses.synthetixV3.dHedgeVaultsWhitelist.length === 0) {
      return console.warn("dHedgeVaultsWhitelist addresses could not be found: skipping.");
    }

    const { abi } = await hre.artifacts.readArtifact("PoolLogic");
    const mintManagerFeeTxData = new ethers.utils.Interface(abi).encodeFunctionData("mintManagerFee", []);

    for (const { poolLogic } of addresses.synthetixV3.dHedgeVaultsWhitelist) {
      await proposeTx(poolLogic, mintManagerFeeTxData, `mintManagerFee on ${poolLogic}`, config, addresses);
    }
  }
};
