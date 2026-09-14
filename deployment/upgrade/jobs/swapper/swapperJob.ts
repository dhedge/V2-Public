import { getDeployData } from "@openzeppelin/hardhat-upgrades/dist/utils/deploy-impl";
import {
  Manifest,
  assertStorageUpgradeSafe,
  assertUpgradeSafe,
  getAdminAddress,
  getImplementationAddress,
  getStorageLayoutForAddress,
} from "@openzeppelin/upgrades-core";
import { HardhatRuntimeEnvironment } from "hardhat/types";

import { proposeTx, tryVerify } from "../../../deploymentHelpers";
import { IAddresses, IFileNames, IJob, IUpgradeConfig, IVersions } from "../../../types";

const SWAPPER = "contracts/swappers/swapper/Swapper.sol:Swapper";

// The Swapper sits behind its own OpenZeppelin v5 ProxyAdmin, which only has `upgradeAndCall`.
const PROXY_ADMIN_ABI = ["function upgradeAndCall(address proxy, address implementation, bytes data) payable"];

export const swapperJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  _filenames: IFileNames,
  addresses: IAddresses,
) => {
  const proxy = addresses.flatMoney?.swapper;
  if (!proxy) return console.warn("Swapper not configured: skipping.");

  console.log("Upgrading Swapper");

  const { ethers, upgrades } = hre;
  const provider = hre.network.provider;

  const currentImplementation = await getImplementationAddress(provider, proxy);
  const proxyAdminAddress = await getAdminAddress(provider, proxy);

  const Swapper = await ethers.getContractFactory(SWAPPER);
  const swapperDeployData = await getDeployData(hre, Swapper, { kind: "transparent" });
  assertUpgradeSafe(swapperDeployData.validations, swapperDeployData.version, swapperDeployData.fullOpts);

  const manifest = await Manifest.forNetwork(provider);
  const currentLayout = await getStorageLayoutForAddress(
    manifest,
    swapperDeployData.validations,
    currentImplementation,
  );
  assertStorageUpgradeSafe(currentLayout, swapperDeployData.layout, swapperDeployData.fullOpts);
  console.log(
    `Storage layout validated against the OpenZeppelin manifest (live implementation ${currentImplementation})`,
  );

  if (config.execute) {
    const newImplementation = await upgrades.prepareUpgrade(proxy, Swapper, { kind: "transparent" });
    console.log("New logic deployed to: ", newImplementation);

    await tryVerify(hre, newImplementation, SWAPPER, []);

    const upgradeABI = new ethers.utils.Interface(PROXY_ADMIN_ABI).encodeFunctionData("upgradeAndCall", [
      proxy,
      newImplementation,
      "0x",
    ]);
    await proposeTx(proxyAdminAddress, upgradeABI, "Upgrade Swapper", config, addresses);

    versions[config.newTag].contracts.SwapperProxy = proxy;
    versions[config.newTag].contracts.Swapper = newImplementation;

    console.log("Swapper upgraded. New implementation address: ", newImplementation);
  } else {
    console.log(`Will propose the upgrade to ProxyAdmin ${proxyAdminAddress}`);
  }
};
