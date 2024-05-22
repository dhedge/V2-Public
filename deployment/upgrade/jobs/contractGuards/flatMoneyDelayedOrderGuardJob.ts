import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx, tryVerify } from "../../../deploymentHelpers";
import { IAddresses, IFileNames, IJob, IUpgradeConfig, IVersions } from "../../../types";
import { addOrReplaceGuardInFile } from "../helpers";

export const flatMoneyDelayedOrderGuardJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  filenames: IFileNames,
  addresses: IAddresses,
) => {
  console.log("Will deploy FlatMoneyDelayedOrderContractGuard");
  const delayedOrder = addresses.flatMoney?.delayedOrder;

  if (!delayedOrder) {
    return console.warn("DelayedOrder address not configured for FlatMoneyDelayedOrderContractGuard. skipping.");
  }

  if (config.execute) {
    const ethers = hre.ethers;

    const FlatMoneyDelayedOrderContractGuard = await ethers.getContractFactory("FlatMoneyDelayedOrderContractGuard");
    const flatMoneyDelayedOrderContractGuard = await FlatMoneyDelayedOrderContractGuard.deploy();
    await flatMoneyDelayedOrderContractGuard.deployed();
    const flatMoneyDelayedOrderContractGuardAddress = flatMoneyDelayedOrderContractGuard.address;
    console.log("FlatMoneyDelayedOrderContractGuard deployed at", flatMoneyDelayedOrderContractGuardAddress);

    versions[config.newTag].contracts.FlatMoneyDelayedOrderContractGuard = flatMoneyDelayedOrderContractGuardAddress;

    await tryVerify(
      hre,
      flatMoneyDelayedOrderContractGuardAddress,
      "contracts/guards/contractGuards/flatMoney/FlatMoneyDelayedOrderContractGuard.sol:FlatMoneyDelayedOrderContractGuard",
      [],
    );

    const Governance = await hre.artifacts.readArtifact("Governance");
    const setContractGuardTxData = new ethers.utils.Interface(Governance.abi).encodeFunctionData("setContractGuard", [
      delayedOrder,
      flatMoneyDelayedOrderContractGuardAddress,
    ]);

    await proposeTx(
      versions[config.oldTag].contracts.Governance,
      setContractGuardTxData,
      "setContractGuard for FlatMoneyDelayedOrderContractGuard",
      config,
      addresses,
    );

    const deployedGuard = {
      contractAddress: delayedOrder,
      guardName: "FlatMoneyDelayedOrderContractGuard",
      guardAddress: flatMoneyDelayedOrderContractGuardAddress,
      description: "Flat Money DelayedOrder Guard",
    };

    await addOrReplaceGuardInFile(filenames.contractGuardsFileName, deployedGuard, "contractAddress");
  }
};
