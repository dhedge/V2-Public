import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx } from "../../../deploymentHelpers";
import { IAddresses, IFileNames, IJob, IUpgradeConfig, IVersions } from "../../../types";

export const hyperliquidCoreWriterApiWalletJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  _filenames: IFileNames,
  addresses: IAddresses,
) => {
  console.log("Will reconcile Hyperliquid API wallet enabled pools");

  const configuredPools = addresses.hyperliquid?.apiWalletEnabledPools;
  if (!configuredPools) {
    return console.warn("apiWalletEnabledPools not configured for HyperliquidCoreWriterContractGuard. Skipping.");
  }

  const coreWriterGuardProxy = versions[config.newTag].contracts.HyperliquidCoreWriterContractGuardProxy;
  if (!coreWriterGuardProxy) {
    return console.warn("HyperliquidCoreWriterContractGuardProxy not found in versions. Skipping.");
  }

  const HyperliquidCoreWriterContractGuard = await hre.artifacts.readArtifact("HyperliquidCoreWriterContractGuard");
  const guardInterface = new hre.ethers.utils.Interface(HyperliquidCoreWriterContractGuard.abi);
  const guardContract = new hre.ethers.Contract(coreWriterGuardProxy, guardInterface, hre.ethers.provider);

  // enable pools that are configured but not yet enabled
  // on-chain, and disable pools that are enabled on-chain but no longer in the config.
  const desiredSet = new Set(configuredPools.map((pool) => hre.ethers.utils.getAddress(pool)));
  const onChainPools: string[] = await guardContract.getApiWalletEnabledPools();
  const onChainSet = new Set(onChainPools.map((pool) => hre.ethers.utils.getAddress(pool)));

  const poolsToEnable = [...desiredSet].filter((pool) => !onChainSet.has(pool));
  const poolsToDisable = [...onChainSet].filter((pool) => !desiredSet.has(pool));

  console.log("API wallet pools to enable: ", poolsToEnable);
  console.log("API wallet pools to disable: ", poolsToDisable);

  if (poolsToEnable.length === 0 && poolsToDisable.length === 0) {
    return console.log("API wallet enabled pools already match deploymentData. Skipping.");
  }

  const settings = [
    ...poolsToEnable.map((poolLogic) => ({ poolLogic, enabled: true })),
    ...poolsToDisable.map((poolLogic) => ({ poolLogic, enabled: false })),
  ];

  const setApiWalletEnabledTxData = guardInterface.encodeFunctionData("setApiWalletEnabled", [settings]);

  if (config.execute) {
    await proposeTx(
      coreWriterGuardProxy,
      setApiWalletEnabledTxData,
      "HyperliquidCoreWriterContractGuard - Reconcile API wallet enabled pools",
      config,
      addresses,
    );
  }
};
