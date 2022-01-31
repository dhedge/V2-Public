import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx, tryVerify } from "../../Helpers";
import { IJob, IProposeTxProperties, IUpgradeConfig, IVersions } from "../../types";

export const assetHandlerJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  // TODO: This optimally should not be mutated
  versions: IVersions,
  _: {},
  addresses: IProposeTxProperties,
) => {
  const ethers = hre.ethers;
  const upgrades = hre.upgrades;

  const ProxyAdmin = await hre.artifacts.readArtifact("ProxyAdmin");
  const proxyAdmin = new ethers.utils.Interface(ProxyAdmin.abi);

  console.log("Will upgrade assethandler");
  if (config.execute) {
    let oldAssetHandler = versions[config.oldTag].contracts.AssetHandlerProxy;
    const AssetHandler = await ethers.getContractFactory("AssetHandler");
    const assetHandler = await upgrades.prepareUpgrade(oldAssetHandler, AssetHandler);
    console.log("assetHandler logic deployed to: ", assetHandler);

    await tryVerify(hre, assetHandler, "contracts/priceAggregators/AssetHandler.sol:AssetHandler", []);

    const upgradeABI = proxyAdmin.encodeFunctionData("upgrade", [oldAssetHandler, assetHandler]);
    await proposeTx(addresses.proxyAdminAddress, upgradeABI, "Upgrade Asset Handler", config, addresses);
  }
};
