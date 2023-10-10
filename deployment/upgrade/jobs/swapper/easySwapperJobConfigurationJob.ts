import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx } from "../../../deploymentHelpers";
import { IAddresses, IFileNames, IJob, IUpgradeConfig, IVersions } from "../../../types";

export const easySwapperConfigurationJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  _filenames: IFileNames,
  addresses: IAddresses,
) => {
  const ethers = hre.ethers;
  const network = await ethers.provider.getNetwork();

  console.log("Network:", network.name);
  console.log("Will update easySwapper configuration");

  if (config.execute) {
    const DhedgeEasySwapper = await hre.artifacts.readArtifact("DhedgeEasySwapper");
    const DhedgeEasySwapperAbi = new ethers.utils.Interface(DhedgeEasySwapper.abi);

    const currentFeeNumerator = versions[config.newTag].config.easySwapperConfig?.feeNumerator || 0;
    const currentFeeDenominator = versions[config.newTag].config.easySwapperConfig?.feeDenominator || 0;

    const newFeeNumerator = addresses.easySwapperConfig.feeNumerator;
    const newFeeDenominator = addresses.easySwapperConfig.feeDenominator;

    if (currentFeeDenominator != newFeeDenominator || currentFeeNumerator != newFeeNumerator) {
      const setAllowed = DhedgeEasySwapperAbi.encodeFunctionData("setFee", [newFeeNumerator, newFeeDenominator]);
      await proposeTx(
        versions[config.newTag].contracts.DhedgeEasySwapperProxy,
        setAllowed,
        `Swapper - set fee ${newFeeNumerator}:${newFeeDenominator}`,
        config,
        addresses,
      );
    }

    const newAllowedPools = addresses.easySwapperConfig.customLockupAllowedPools;
    const existingAllowedPools = versions[config.newTag].config.easySwapperConfig?.customLockupAllowedPools || [];
    // Any that are removed from the config are set to not allowed
    const removedPools = existingAllowedPools.filter((existing) => {
      return newAllowedPools.indexOf(existing) == -1;
    });
    // Any that are added to the config are set to allowed
    const addedPools = newAllowedPools.filter((existing) => {
      return existingAllowedPools.indexOf(existing) == -1;
    });

    for (const pool of addedPools) {
      const setAllowed = DhedgeEasySwapperAbi.encodeFunctionData("setPoolAllowed", [pool, true]);
      await proposeTx(
        versions[config.newTag].contracts.DhedgeEasySwapperProxy,
        setAllowed,
        `Swapper - Add new Allowed Pool ${pool}`,
        config,
        addresses,
      );
    }

    for (const pool of removedPools) {
      const setAllowed = DhedgeEasySwapperAbi.encodeFunctionData("setPoolAllowed", [pool, false]);
      await proposeTx(
        versions[config.newTag].contracts.DhedgeEasySwapperProxy,
        setAllowed,
        `Swapper - Remove Allowed Pool ${pool}`,
        config,
        addresses,
      );
    }

    const newFeeBypassManagers = addresses.easySwapperConfig.feeByPassManagers;
    const existingFeeBypassManagers = versions[config.newTag].config.easySwapperConfig?.feeByPassManagers || [];
    // Any that are removed from the config are set to not allowed
    const removedManagers = existingFeeBypassManagers.filter((existing) => {
      return newFeeBypassManagers.indexOf(existing) == -1;
    });
    // Any that are added to the config are set to allowed
    const addedManagers = newFeeBypassManagers.filter((existing) => {
      return existingFeeBypassManagers.indexOf(existing) == -1;
    });

    for (const manager of addedManagers) {
      const setAllowed = DhedgeEasySwapperAbi.encodeFunctionData("setManagerFeeBypass", [manager, true]);
      await proposeTx(
        versions[config.newTag].contracts.DhedgeEasySwapperProxy,
        setAllowed,
        `Swapper - Add new FeeBypass Manager ${manager}`,
        config,
        addresses,
      );
    }

    for (const manager of removedManagers) {
      const setAllowed = DhedgeEasySwapperAbi.encodeFunctionData("setManagerFeeBypass", [manager, false]);
      await proposeTx(
        versions[config.newTag].contracts.DhedgeEasySwapperProxy,
        setAllowed,
        `Remove FeeBypass Manager ${manager}`,
        config,
        addresses,
      );
    }

    versions[config.newTag].config.easySwapperConfig = addresses.easySwapperConfig;
  }
};
