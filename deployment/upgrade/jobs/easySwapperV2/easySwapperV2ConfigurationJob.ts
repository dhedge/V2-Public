import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx } from "../../../deploymentHelpers";
import { IAddresses, IFileNames, IJob, IUpgradeConfig, IVersions } from "../../../types";
import { WhitelistSettingStruct } from "../../../../types/EasySwapperV2";

export const easySwapperV2ConfigurationJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  _filenames: IFileNames,
  addresses: IAddresses,
) => {
  console.log("Will update EasySwapperV2 configuration");

  const EasySwapperV2 = await hre.artifacts.readArtifact("EasySwapperV2");
  const EasySwapperV2Abi = new hre.ethers.utils.Interface(EasySwapperV2.abi);

  const newConfigVaults = addresses.easySwapperV2.customCooldownDepositsWhitelist;
  const existingVaults = versions[config.newTag].config.easySwapperV2?.customCooldownDepositsWhitelist ?? [];

  // Any that are added to the config are added to the whitelist
  const addedVaults: WhitelistSettingStruct[] = newConfigVaults
    .filter((newVault) => !existingVaults.some((existingVault) => existingVault === newVault))
    .map((dHedgeVault) => ({ toWhitelist: dHedgeVault, whitelisted: true }));

  // Any that are removed from the config are removed from the whitelist
  const removedVaults: WhitelistSettingStruct[] = existingVaults
    .filter((existingVault) => !newConfigVaults.some((newVault) => newVault === existingVault))
    .map((dHedgeVault) => ({ toWhitelist: dHedgeVault, whitelisted: false }));

  const newCustomCooldownWhitelist = [...addedVaults, ...removedVaults];

  console.log("New custom cooldown whitelist: ", newCustomCooldownWhitelist);

  if (newCustomCooldownWhitelist.length === 0) return;

  const setCustomCooldownWhitelistTxData = EasySwapperV2Abi.encodeFunctionData("setCustomCooldownWhitelist", [
    newCustomCooldownWhitelist,
  ]);

  if (config.execute) {
    await proposeTx(
      versions[config.newTag].contracts.EasySwapperV2Proxy,
      setCustomCooldownWhitelistTxData,
      `EasySwapperV2 - Set new custom cooldown whitelist`,
      config,
      addresses,
    );

    versions[config.newTag].config.easySwapperV2 = addresses.easySwapperV2;
  }
};
