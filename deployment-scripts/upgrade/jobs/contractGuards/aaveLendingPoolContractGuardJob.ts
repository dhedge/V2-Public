import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx, tryVerify } from "../../../Helpers";
import { addOrReplaceGuardInFile } from "../helpers";
import { IJob, IProposeTxProperties, IUpgradeConfig, IVersions } from "../../../types";

export const aaveLendingPoolContractGuardJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  // TODO: This optimally should not be mutated
  versions: IVersions,
  filenames: { contractGuardsFileName: string },
  addresses: { aaveLendingPoolAddress?: string } & IProposeTxProperties,
) => {
  if (!addresses.aaveLendingPoolAddress) {
    console.warn("aaveLendingPoolAddress not configured for aaveIncentivesControllerContractGuard: skipping.");
    return;
  }

  const ethers = hre.ethers;
  const Governance = await hre.artifacts.readArtifact("Governance");
  const governanceABI = new ethers.utils.Interface(Governance.abi);

  console.log("Will deploy aavelendingpoolguard");
  if (config.execute) {
    const AaveLendingPoolGuard = await ethers.getContractFactory("AaveLendingPoolGuard");
    const aaveLendingPoolGuard = await AaveLendingPoolGuard.deploy();
    await aaveLendingPoolGuard.deployed();
    console.log("AaveLendingPoolGuard deployed at", aaveLendingPoolGuard.address);
    versions[config.newTag].contracts.AaveLendingPoolGuard = aaveLendingPoolGuard.address;

    await tryVerify(
      hre,
      aaveLendingPoolGuard.address,
      "contracts/guards/contractGuards/AaveLendingPoolGuard.sol:AaveLendingPoolGuard",
      [],
    );

    const setContractGuardABI = governanceABI.encodeFunctionData("setContractGuard", [
      addresses.aaveLendingPoolAddress,
      aaveLendingPoolGuard.address,
    ]);
    await proposeTx(
      versions[config.oldTag].contracts.Governance,
      setContractGuardABI,
      "setContractGuard for aaveLendingPoolGuard",
      config,
      addresses,
    );

    const deployedGuard = {
      ContractAddress: addresses.aaveLendingPoolAddress,
      GuardName: "AaveLendingPoolGuard",
      GuardAddress: aaveLendingPoolGuard.address,
      Description: "Aave Lending Pool contract",
    };
    await addOrReplaceGuardInFile(filenames.contractGuardsFileName, deployedGuard, "ContractAddress");
  }
};
