import { HardhatRuntimeEnvironment } from "hardhat/types";

import { proposeTx, proposeTransactions, tryVerify } from "../../../deploymentHelpers";
import { IAddresses, IFileNames, IJob, IUpgradeConfig, IVersions } from "../../../types";

/// Set to true to remove the previous EasyLimitBuyManager from custom cooldown whitelist before adding the new one
const REMOVE_PREVIOUS_FROM_COOLDOWN_WHITELIST = false;

export const easyLimitBuyManagerJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  _filenames: IFileNames,
  addresses: IAddresses,
) => {
  const previousEasyLimitBuyManager = versions[config.newTag].contracts.EasyLimitBuyManager;

  console.log("Deploying EasyLimitBuyManager");

  const ethers = hre.ethers;

  const poolFactoryProxy = versions[config.newTag].contracts.PoolFactoryProxy;
  const easySwapperV2Proxy = versions[config.newTag].contracts.EasySwapperV2Proxy;

  if (!poolFactoryProxy) return console.warn("PoolFactoryProxy missing... skipping.");
  if (!easySwapperV2Proxy) return console.warn("EasySwapperV2Proxy missing... skipping.");

  const permit2Address = addresses.easyLimitBuyManager.permit2;
  if (!permit2Address) return console.warn("Permit2 address missing... skipping.");

  const [deployer] = await ethers.getSigners();

  if (config.execute) {
    const EasyLimitBuyManager = await ethers.getContractFactory("EasyLimitBuyManager");
    const easyLimitBuyManager = await EasyLimitBuyManager.deploy(
      deployer.address,
      permit2Address,
      poolFactoryProxy,
      easySwapperV2Proxy,
    );
    await easyLimitBuyManager.deployed();
    const easyLimitBuyManagerAddress = easyLimitBuyManager.address;

    await tryVerify(
      hre,
      easyLimitBuyManagerAddress,
      "contracts/limitOrders/EasyLimitBuyManager.sol:EasyLimitBuyManager",
      [deployer.address, permit2Address, poolFactoryProxy, easySwapperV2Proxy],
    );

    versions[config.newTag].contracts.EasyLimitBuyManager = easyLimitBuyManagerAddress;

    console.log("EasyLimitBuyManager deployed to: ", easyLimitBuyManagerAddress);

    // Whitelist EasyLimitBuyManager in PoolFactory for custom cooldown
    const PoolFactory = await hre.artifacts.readArtifact("PoolFactory");
    const poolFactoryInterface = new ethers.utils.Interface(PoolFactory.abi);

    if (REMOVE_PREVIOUS_FROM_COOLDOWN_WHITELIST && previousEasyLimitBuyManager) {
      const removeCustomCooldownWhitelistTxData = poolFactoryInterface.encodeFunctionData(
        "removeCustomCooldownWhitelist",
        [previousEasyLimitBuyManager],
      );
      const addCustomCooldownWhitelistTxData = poolFactoryInterface.encodeFunctionData("addCustomCooldownWhitelist", [
        easyLimitBuyManagerAddress,
      ]);
      await proposeTransactions(
        [
          { to: poolFactoryProxy, value: "0", data: removeCustomCooldownWhitelistTxData },
          { to: poolFactoryProxy, value: "0", data: addCustomCooldownWhitelistTxData },
        ],
        "Remove previous and whitelist new EasyLimitBuyManager in PoolFactory for custom cooldown",
        config,
        addresses,
      );
    } else {
      const addCustomCooldownWhitelistTxData = poolFactoryInterface.encodeFunctionData("addCustomCooldownWhitelist", [
        easyLimitBuyManagerAddress,
      ]);
      await proposeTx(
        poolFactoryProxy,
        addCustomCooldownWhitelistTxData,
        "Whitelist EasyLimitBuyManager in PoolFactory for custom cooldown",
        config,
        addresses,
      );
    }
  }
};
