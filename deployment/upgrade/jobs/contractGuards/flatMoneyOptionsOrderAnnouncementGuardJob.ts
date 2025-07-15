import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx, tryVerify } from "../../../deploymentHelpers";
import { IAddresses, IFileNames, IJob, IUpgradeConfig, IVersions } from "../../../types";
import { addOrReplaceGuardInFile } from "../helpers";

export const flatMoneyOptionsOrderAnnouncementGuardJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  filenames: IFileNames,
  addresses: IAddresses,
) => {
  console.log("Will deploy FlatMoneyOptionsOrderAnnouncementGuard");
  const orderAnnouncementModule = addresses.flatMoneyOptions?.orderAnnouncementModule;

  if (!orderAnnouncementModule)
    return console.warn(
      "OrderAnnouncementModule address not configured for FlatMoneyOptionsOrderAnnouncementGuard. skipping.",
    );

  const nftTrackerStorage = versions[config.oldTag].contracts.DhedgeNftTrackerStorageProxy;

  if (!nftTrackerStorage) return console.warn("DhedgeNftTrackerStorage could not be found: skipping.");

  if (config.execute) {
    const ethers = hre.ethers;

    const FlatMoneyOptionsOrderAnnouncementGuard = await ethers.getContractFactory(
      "FlatMoneyOptionsOrderAnnouncementGuard",
    );
    const args: Parameters<typeof FlatMoneyOptionsOrderAnnouncementGuard.deploy> = [
      nftTrackerStorage,
      "0x77b5498047b3c24d335f231c790c09b91f4c09eab7920578bb188978f18926c7", // keccak256("FLAT_MONEY_V2_LEVERAGE_NFT")
      1,
      [],
      "10000000000000000000", // 10e18
    ];
    const flatMoneyOptionsOrderAnnouncementGuard = await FlatMoneyOptionsOrderAnnouncementGuard.deploy(...args);
    await flatMoneyOptionsOrderAnnouncementGuard.deployed();
    const flatMoneyOptionsOrderAnnouncementGuardAddress = flatMoneyOptionsOrderAnnouncementGuard.address;
    console.log("FlatMoneyOptionsOrderAnnouncementGuard deployed at", flatMoneyOptionsOrderAnnouncementGuardAddress);

    versions[config.newTag].contracts.FlatMoneyOptionsOrderAnnouncementGuard =
      flatMoneyOptionsOrderAnnouncementGuardAddress;

    await tryVerify(
      hre,
      flatMoneyOptionsOrderAnnouncementGuardAddress,
      "contracts/guards/contractGuards/flatMoney/v2/FlatMoneyOptionsOrderAnnouncementGuard.sol:FlatMoneyOptionsOrderAnnouncementGuard",
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
      "setContractGuard for FlatMoneyOptionsOrderAnnouncementGuard",
      config,
      addresses,
    );

    const deployedGuard = {
      contractAddress: orderAnnouncementModule,
      guardName: "FlatMoneyOptionsOrderAnnouncementGuard",
      guardAddress: flatMoneyOptionsOrderAnnouncementGuardAddress,
      description: "Flat Money OrderAnnouncementModule Guard",
    };

    await addOrReplaceGuardInFile(filenames.contractGuardsFileName, deployedGuard, "contractAddress");
  }
};
