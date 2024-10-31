import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx, tryVerify } from "../../../deploymentHelpers";
import { addOrReplaceGuardInFile } from "../helpers";
import { IAddresses, IJob, IUpgradeConfig, IVersions, IFileNames } from "../../../types";

export const aaveV2LendingPoolContractGuardJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  filenames: IFileNames,
  addresses: IAddresses,
) => {
  if (!addresses.aaveV2?.aaveLendingPoolAddress) {
    console.warn("aaveLendingPoolAddress not configured for aaveV2LendingPoolContractGuardJob: skipping.");
    return;
  }

  const ethers = hre.ethers;
  const Governance = await hre.artifacts.readArtifact("Governance");
  const governanceABI = new ethers.utils.Interface(Governance.abi);

  console.log("Will deploy aavev2lendingpoolguard");
  if (config.execute) {
    const AaveLendingPoolGuard = await ethers.getContractFactory("AaveLendingPoolGuardV2");
    const aaveLendingPoolGuard = await AaveLendingPoolGuard.deploy();
    await aaveLendingPoolGuard.deployed();
    console.log("AaveLendingPoolGuardV2 deployed at", aaveLendingPoolGuard.address);
    versions[config.newTag].contracts.AaveLendingPoolGuardV2 = aaveLendingPoolGuard.address;

    await tryVerify(
      hre,
      aaveLendingPoolGuard.address,
      "contracts/guards/contractGuards/AaveLendingPoolGuardV2.sol:AaveLendingPoolGuardV2",
      [],
    );

    const setContractGuardABI = governanceABI.encodeFunctionData("setContractGuard", [
      addresses.aaveV2.aaveLendingPoolAddress,
      aaveLendingPoolGuard.address,
    ]);
    await proposeTx(
      versions[config.oldTag].contracts.Governance,
      setContractGuardABI,
      "setContractGuard for Aave V2 Lending Pool",
      config,
      addresses,
    );

    const deployedGuard = {
      contractAddress: addresses.aaveV2.aaveLendingPoolAddress,
      guardName: "AaveLendingPoolGuardV2",
      guardAddress: aaveLendingPoolGuard.address,
      description: "Aave V2 Lending Pool contract",
    };
    await addOrReplaceGuardInFile(filenames.contractGuardsFileName, deployedGuard, "contractAddress");
  }
};
