import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx, tryVerify } from "../../../deploymentHelpers";
import { addOrReplaceGuardInFile } from "../helpers";
import { IAddresses, IJob, IUpgradeConfig, IVersions, IFileNames } from "../../../types";

export const aaveV3LendingPoolContractGuardJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  filenames: IFileNames,
  addresses: IAddresses,
) => {
  if (!addresses.aaveV3?.aaveLendingPoolAddress) {
    console.warn("aaveLendingPoolAddress not configured for aaveV3LendingPoolContractGuardJob: skipping.");
    return;
  }

  const ethers = hre.ethers;
  const Governance = await hre.artifacts.readArtifact("Governance");
  const governanceABI = new ethers.utils.Interface(Governance.abi);

  const chainName = hre.network.name;

  const contractName =
    chainName === "arbitrum" || chainName === "base" || chainName === "ovm"
      ? "AaveLendingPoolGuardV3L2Pool"
      : "AaveLendingPoolGuardV3";

  console.log(`Will deploy ${contractName}`);

  if (config.execute) {
    const AaveLendingPoolGuardV3 = await ethers.getContractFactory(contractName);
    const aaveLendingPoolGuardV3 = await AaveLendingPoolGuardV3.deploy();
    await aaveLendingPoolGuardV3.deployed();
    console.log(`${contractName} deployed at`, aaveLendingPoolGuardV3.address);
    versions[config.newTag].contracts[contractName] = aaveLendingPoolGuardV3.address;

    await tryVerify(
      hre,
      aaveLendingPoolGuardV3.address,
      `contracts/guards/contractGuards/${contractName}.sol:${contractName}`,
      [],
    );

    const setContractGuardABI = governanceABI.encodeFunctionData("setContractGuard", [
      addresses.aaveV3.aaveLendingPoolAddress,
      aaveLendingPoolGuardV3.address,
    ]);
    await proposeTx(
      versions[config.oldTag].contracts.Governance,
      setContractGuardABI,
      "setContractGuard for Aave V3 Lending Pool",
      config,
      addresses,
    );

    const deployedGuard = {
      contractAddress: addresses.aaveV3.aaveLendingPoolAddress,
      guardName: contractName,
      guardAddress: aaveLendingPoolGuardV3.address,
      description: "Aave V3 Lending Pool contract",
    };
    await addOrReplaceGuardInFile(filenames.contractGuardsFileName, deployedGuard, "contractAddress");
  }
};
