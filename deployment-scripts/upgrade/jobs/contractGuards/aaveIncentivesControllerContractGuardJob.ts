import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx, tryVerify } from "../../../Helpers";
import { addOrReplaceGuardInFile } from "../helpers";
import { IJob, IProposeTxProperties, IUpgradeConfig, IVersions } from "../../../types";

export const aaveIncentivesControllerContractGuardJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  // TODO: This optimally should not be mutated
  versions: IVersions,
  filenames: { contractGuardsFileName: string },
  addresses: { aaveIncentivesControllerAddress?: string; wmaticTokenAddress?: string } & IProposeTxProperties,
) => {
  if (!addresses.aaveIncentivesControllerAddress) {
    console.warn("aaveIncentivesControllerAddress not configured for aaveIncentivesControllerContractGuard: skipping.");
    return;
  }
  if (!addresses.wmaticTokenAddress) {
    console.warn("wmaticTokenAddress not configured for aaveIncentivesControllerContractGuard: skipping.");
    return;
  }

  //
  // Todo: This Job needs to be made more generic not all chains will have wmatic incentives
  //

  const ethers = hre.ethers;
  const Governance = await hre.artifacts.readArtifact("Governance");
  const governanceABI = new ethers.utils.Interface(Governance.abi);

  console.log("Will deploy aaveincentivescontrollerguard");
  if (config.execute) {
    const AaveIncentivesControllerGuard = await ethers.getContractFactory("AaveIncentivesControllerGuard");
    console.log("wmatic: ", addresses.wmaticTokenAddress);
    const aaveIncentivesControllerGuard = await AaveIncentivesControllerGuard.deploy(addresses.wmaticTokenAddress);
    await aaveIncentivesControllerGuard.deployed();
    console.log("AaveIncentivesControllerGuard deployed at", aaveIncentivesControllerGuard.address);
    versions[config.newTag].contracts.AaveIncentivesControllerGuard = aaveIncentivesControllerGuard.address;

    await tryVerify(
      hre,
      aaveIncentivesControllerGuard.address,
      "contracts/guards/contractGuards/AaveIncentivesControllerGuard.sol:AaveIncentivesControllerGuard",
      [addresses.wmaticTokenAddress],
    );

    const setContractGuardABI = governanceABI.encodeFunctionData("setContractGuard", [
      addresses.aaveIncentivesControllerAddress,
      aaveIncentivesControllerGuard.address,
    ]);
    await proposeTx(
      versions[config.oldTag].contracts.Governance,
      setContractGuardABI,
      "setContractGuard for AaveIncentivesControllerGuard",
      config,
      addresses,
    );
    const deployedGuard = {
      contractAddress: addresses.aaveIncentivesControllerAddress,
      guardName: "AaveIncentivesControllerGuard",
      guardAddress: aaveIncentivesControllerGuard.address,
      description: "Aave Incentives Controller contract",
    };
    await addOrReplaceGuardInFile(filenames.contractGuardsFileName, deployedGuard, "contractAddress");
  }
};
