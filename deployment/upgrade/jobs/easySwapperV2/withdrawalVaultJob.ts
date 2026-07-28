import { getImplementationAddress } from "@openzeppelin/upgrades-core";
import { HardhatRuntimeEnvironment } from "hardhat/types";

import { proposeTx, tryVerify } from "../../../deploymentHelpers";
import { IAddresses, IFileNames, IJob, IUpgradeConfig, IVersions } from "../../../types";

export const withdrawalVaultJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  _filenames: IFileNames,
  addresses: IAddresses,
) => {
  const ethers = hre.ethers;
  const upgrades = hre.upgrades;

  if (config.execute) {
    const proxy = versions[config.oldTag].contracts.WithdrawalVaultProxy;

    // DytmWithdrawLib is an external library linked into WithdrawalVault. Redeploy on every
    // upgrade to mirror the `PoolLogicLib` pattern in `poolLogicJob.ts`.
    const DytmWithdrawLib = await ethers.getContractFactory("DytmWithdrawLib");
    const dytmWithdrawLib = await DytmWithdrawLib.deploy();
    await dytmWithdrawLib.deployed();
    console.log("DytmWithdrawLib deployed at:", dytmWithdrawLib.address);
    versions[config.newTag].contracts.DytmWithdrawLib = dytmWithdrawLib.address;

    await tryVerify(
      hre,
      dytmWithdrawLib.address,
      "contracts/swappers/easySwapperV2/libraries/dytm/DytmWithdrawLib.sol:DytmWithdrawLib",
      [],
    );

    const WithdrawalVault = await ethers.getContractFactory("WithdrawalVault", {
      libraries: {
        DytmWithdrawLib: dytmWithdrawLib.address,
      },
    });

    if (proxy) {
      console.log("Will upgrade WithdrawalVault");

      const newImplementation = await upgrades.prepareUpgrade(proxy, WithdrawalVault, {
        unsafeAllow: ["external-library-linking"],
      });

      console.log("WithdrawalVault deployed to: ", newImplementation);
      versions[config.newTag].contracts.WithdrawalVault = newImplementation;

      await tryVerify(
        hre,
        newImplementation,
        "contracts/swappers/easySwapperV2/WithdrawalVault.sol:WithdrawalVault",
        [],
      );

      const EasySwapperV2 = await hre.artifacts.readArtifact("EasySwapperV2");
      const setLogicABI = new ethers.utils.Interface(EasySwapperV2.abi).encodeFunctionData("setLogic", [
        newImplementation,
      ]);
      await proposeTx(
        versions[config.oldTag].contracts.EasySwapperV2Proxy,
        setLogicABI,
        "Set logic for WithdrawalVault",
        config,
        addresses,
      );
    } else {
      console.log("Will deploy WithdrawalVault");

      const withdrawalVaultProxy = await upgrades.deployProxy(WithdrawalVault, [], {
        initializer: false,
        unsafeAllow: ["external-library-linking"],
      });
      await withdrawalVaultProxy.deployed();

      console.log("WithdrawalVaultProxy deployed at: ", withdrawalVaultProxy.address);

      const withdrawalVaultImplementationAddress = await getImplementationAddress(
        ethers.provider,
        withdrawalVaultProxy.address,
      );

      await tryVerify(
        hre,
        withdrawalVaultImplementationAddress,
        "contracts/swappers/easySwapperV2/WithdrawalVault.sol:WithdrawalVault",
        [],
      );

      versions[config.newTag].contracts.WithdrawalVaultProxy = withdrawalVaultProxy.address;
      versions[config.newTag].contracts.WithdrawalVault = withdrawalVaultImplementationAddress;
    }
  }
};
