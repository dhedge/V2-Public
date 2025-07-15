import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx, tryVerify } from "../../../deploymentHelpers";
import { IAddresses, IFileNames, IJob, IUpgradeConfig, IVersions } from "../../../types";
import { addOrReplaceGuardInFile } from "../helpers";

export const flatMoneyV2OrderExecutionGuardJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  filenames: IFileNames,
  addresses: IAddresses,
) => {
  console.log("Will deploy FlatMoneyV2OrderExecutionGuard");
  const orderExecutionModule = addresses.flatMoneyV2?.orderExecutionModule;
  const whitelitedVaults = addresses.flatMoneyV2?.whitelistedVaults;

  if (!orderExecutionModule || !whitelitedVaults || whitelitedVaults.length === 0)
    return console.warn("Deployment data not configured for FlatMoneyV2OrderExecutionGuard. skipping.");

  const nftTrackerStorage = versions[config.oldTag].contracts.DhedgeNftTrackerStorageProxy;

  if (!nftTrackerStorage) return console.warn("DhedgeNftTrackerStorage could not be found: skipping.");

  if (config.execute) {
    const ethers = hre.ethers;

    const FlatMoneyV2OrderExecutionGuard = await ethers.getContractFactory("FlatMoneyV2OrderExecutionGuard");
    const args: Parameters<typeof FlatMoneyV2OrderExecutionGuard.deploy> = [nftTrackerStorage, whitelitedVaults];
    const flatMoneyV2OrderExecutionGuard = await FlatMoneyV2OrderExecutionGuard.deploy(...args);
    await flatMoneyV2OrderExecutionGuard.deployed();
    const flatMoneyOptionsOrderExecutionGuardAddress = flatMoneyV2OrderExecutionGuard.address;
    console.log("FlatMoneyV2OrderExecutionGuard deployed at", flatMoneyOptionsOrderExecutionGuardAddress);

    versions[config.newTag].contracts.FlatMoneyV2OrderExecutionGuard = flatMoneyOptionsOrderExecutionGuardAddress;

    await tryVerify(
      hre,
      flatMoneyOptionsOrderExecutionGuardAddress,
      "contracts/guards/contractGuards/flatMoney/v2/FlatMoneyV2OrderExecutionGuard.sol:FlatMoneyV2OrderExecutionGuard",
      args,
    );

    const Governance = await hre.artifacts.readArtifact("Governance");
    const setContractGuardTxData = new ethers.utils.Interface(Governance.abi).encodeFunctionData("setContractGuard", [
      orderExecutionModule,
      flatMoneyOptionsOrderExecutionGuardAddress,
    ]);

    await proposeTx(
      versions[config.oldTag].contracts.Governance,
      setContractGuardTxData,
      "setContractGuard for FlatMoneyV2OrderExecutionGuard",
      config,
      addresses,
    );

    const deployedGuard = {
      contractAddress: orderExecutionModule,
      guardName: "FlatMoneyV2OrderExecutionGuard",
      guardAddress: flatMoneyOptionsOrderExecutionGuardAddress,
      description: "Flat Money V2 OrderExecutionModule Guard",
    };

    await addOrReplaceGuardInFile(filenames.contractGuardsFileName, deployedGuard, "contractAddress");
  }
};
