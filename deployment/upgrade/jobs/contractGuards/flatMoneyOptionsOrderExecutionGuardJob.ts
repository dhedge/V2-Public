import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx, tryVerify } from "../../../deploymentHelpers";
import { IAddresses, IFileNames, IJob, IUpgradeConfig, IVersions } from "../../../types";
import { addOrReplaceGuardInFile } from "../helpers";

export const flatMoneyOptionsOrderExecutionGuardJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  filenames: IFileNames,
  addresses: IAddresses,
) => {
  console.log("Will deploy FlatMoneyOptionsOrderExecutionGuard");
  const orderExecutionModule = addresses.flatMoneyOptions?.orderExecutionModule;
  const flatcoinVault = addresses.flatMoneyOptions?.flatcoinVault;

  if (!orderExecutionModule || !flatcoinVault)
    return console.warn(
      "OrderExecutionModule address not configured for FlatMoneyOptionsOrderExecutionGuard. skipping.",
    );

  const nftTrackerStorage = versions[config.oldTag].contracts.DhedgeNftTrackerStorageProxy;

  if (!nftTrackerStorage) return console.warn("DhedgeNftTrackerStorage could not be found: skipping.");

  if (config.execute) {
    const ethers = hre.ethers;

    const FlatMoneyOptionsOrderExecutionGuard = await ethers.getContractFactory("FlatMoneyOptionsOrderExecutionGuard");
    const args: Parameters<typeof FlatMoneyOptionsOrderExecutionGuard.deploy> = [nftTrackerStorage, flatcoinVault];
    const flatMoneyOptionsOrderExecutionGuard = await FlatMoneyOptionsOrderExecutionGuard.deploy(...args);
    await flatMoneyOptionsOrderExecutionGuard.deployed();
    const flatMoneyOptionsOrderExecutionGuardAddress = flatMoneyOptionsOrderExecutionGuard.address;
    console.log("FlatMoneyOptionsOrderExecutionGuard deployed at", flatMoneyOptionsOrderExecutionGuardAddress);

    versions[config.newTag].contracts.FlatMoneyOptionsOrderExecutionGuard = flatMoneyOptionsOrderExecutionGuardAddress;

    await tryVerify(
      hre,
      flatMoneyOptionsOrderExecutionGuardAddress,
      "contracts/guards/contractGuards/flatMoney/v2/FlatMoneyOptionsOrderExecutionGuard.sol:FlatMoneyOptionsOrderExecutionGuard",
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
      "setContractGuard for FlatMoneyOptionsOrderExecutionGuard",
      config,
      addresses,
    );

    const deployedGuard = {
      contractAddress: orderExecutionModule,
      guardName: "FlatMoneyOptionsOrderExecutionGuard",
      guardAddress: flatMoneyOptionsOrderExecutionGuardAddress,
      description: "Flat Money OrderExecutionModule Guard",
    };

    await addOrReplaceGuardInFile(filenames.contractGuardsFileName, deployedGuard, "contractAddress");
  }
};
