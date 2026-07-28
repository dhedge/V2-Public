import { HardhatRuntimeEnvironment } from "hardhat/types";

import { proposeTx, tryVerify } from "../../../deploymentHelpers";
import { IDeployedContractGuard, IJob, IUpgradeConfig, IVersions, IFileNames, IAddresses } from "../../../types";
import { addOrReplaceGuardInFile } from "../helpers";

export const liquifiRewardsContractGuardJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  filenames: IFileNames,
  addresses: IAddresses,
) => {
  const ethers = hre.ethers;

  console.log("Will deploy LiquifiRewardsContractGuard");

  const unverifiedLiquifiClaimer = "0xA4D47A2ca5F11175323155E1258bB15932f0534C";

  if (config.execute) {
    const liquifiRewardsContractGuardFactory = await ethers.getContractFactory("LiquifiRewardsContractGuard");
    const liquifiRewardsContractGuard = await liquifiRewardsContractGuardFactory.deploy();
    await liquifiRewardsContractGuard.deployed();
    const liquifiRewardsContractGuardAddress = liquifiRewardsContractGuard.address;

    console.log("LiquifiRewardsContractGuard deployed at: ", liquifiRewardsContractGuardAddress);

    versions[config.newTag].contracts.LiquifiRewardsContractGuard = liquifiRewardsContractGuardAddress;

    await tryVerify(
      hre,
      liquifiRewardsContractGuardAddress,
      "contracts/guards/contractGuards/LiquifiRewardsContractGuard.sol:LiquifiRewardsContractGuard",
      [],
    );

    const Governance = await hre.artifacts.readArtifact("Governance");
    await proposeTx(
      versions[config.oldTag].contracts.Governance,
      new ethers.utils.Interface(Governance.abi).encodeFunctionData("setContractGuard", [
        unverifiedLiquifiClaimer,
        liquifiRewardsContractGuardAddress,
      ]),
      "setContractGuard for LiquifiRewardsClaimer",
      config,
      addresses,
    );

    const deployedGuard: IDeployedContractGuard = {
      contractAddress: unverifiedLiquifiClaimer,
      guardName: "LiquifiRewardsContractGuard",
      guardAddress: liquifiRewardsContractGuardAddress,
      description: "Liquifi sENA rewards claimer",
    };
    await addOrReplaceGuardInFile(filenames.contractGuardsFileName, deployedGuard, "contractAddress");
  }
};
