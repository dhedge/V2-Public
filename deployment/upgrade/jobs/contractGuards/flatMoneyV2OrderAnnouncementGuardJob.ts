import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx, tryVerify } from "../../../deploymentHelpers";
import { IAddresses, IFileNames, IJob, IUpgradeConfig, IVersions } from "../../../types";
import { addOrReplaceGuardInFile } from "../helpers";

export const flatMoneyV2OrderAnnouncementGuardJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  filenames: IFileNames,
  addresses: IAddresses,
) => {
  console.log("Will deploy FlatMoneyV2OrderAnnouncementGuard");
  const orderAnnouncementModule = addresses.flatMoneyV2?.orderAnnouncementModule;

  if (!orderAnnouncementModule)
    return console.warn(
      "OrderAnnouncementModule address not configured for FlatMoneyV2OrderAnnouncementGuard. skipping.",
    );

  const whitelistedVaults = addresses.flatMoneyV2?.whitelistedVaults;

  if (!whitelistedVaults || whitelistedVaults.length === 0)
    return console.warn("Whitelisted vaults address not configured for FlatMoneyV2OrderAnnouncementGuard. skipping.");

  const nftTrackerStorage = versions[config.oldTag].contracts.DhedgeNftTrackerStorageProxy;

  if (!nftTrackerStorage) return console.warn("DhedgeNftTrackerStorage could not be found: skipping.");

  if (config.execute) {
    const ethers = hre.ethers;

    const FlatMoneyV2OrderAnnouncementGuard = await ethers.getContractFactory("FlatMoneyV2OrderAnnouncementGuard");
    const args: Parameters<typeof FlatMoneyV2OrderAnnouncementGuard.deploy> = [nftTrackerStorage, whitelistedVaults];
    const flatMoneyV2OrderAnnouncementGuard = await FlatMoneyV2OrderAnnouncementGuard.deploy(...args);
    await flatMoneyV2OrderAnnouncementGuard.deployed();
    const flatMoneyOptionsOrderAnnouncementGuardAddress = flatMoneyV2OrderAnnouncementGuard.address;
    console.log("FlatMoneyV2OrderAnnouncementGuard deployed at", flatMoneyOptionsOrderAnnouncementGuardAddress);

    versions[config.newTag].contracts.FlatMoneyV2OrderAnnouncementGuard = flatMoneyOptionsOrderAnnouncementGuardAddress;

    await tryVerify(
      hre,
      flatMoneyOptionsOrderAnnouncementGuardAddress,
      "contracts/guards/contractGuards/flatMoney/v2/FlatMoneyV2OrderAnnouncementGuard.sol:FlatMoneyV2OrderAnnouncementGuard",
      args,
    );

    const Governance = await hre.artifacts.readArtifact("Governance");
    const setContractGuardTxData = new ethers.utils.Interface(Governance.abi).encodeFunctionData("setContractGuard", [
      orderAnnouncementModule,
      flatMoneyOptionsOrderAnnouncementGuardAddress,
    ]);

    await proposeTx(
      versions[config.oldTag].contracts.Governance,
      setContractGuardTxData,
      "setContractGuard for FlatMoneyV2OrderAnnouncementGuard",
      config,
      addresses,
    );

    const deployedGuard = {
      contractAddress: orderAnnouncementModule,
      guardName: "FlatMoneyV2OrderAnnouncementGuard",
      guardAddress: flatMoneyOptionsOrderAnnouncementGuardAddress,
      description: "Flat Money V2 OrderAnnouncementModule Guard",
    };

    await addOrReplaceGuardInFile(filenames.contractGuardsFileName, deployedGuard, "contractAddress");
  }
};
