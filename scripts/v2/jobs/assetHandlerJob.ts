import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx, tryVerify } from "../../Helpers";
import { IJob, IUpgradeConfig } from "../types";

export const assetHandlerJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  // TODO: This should be types and optimally should not be mutated
  versions: any,
  _: {},
  addresses: { proxyAdminAddress: string },
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
    await proposeTx(
      addresses.proxyAdminAddress,
      upgradeABI,
      "Upgrade Asset Handler",
      config.execute,
      config.restartnonce,
    );
  }
};
