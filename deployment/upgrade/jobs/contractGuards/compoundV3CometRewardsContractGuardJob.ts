import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx, tryVerify } from "../../../deploymentHelpers";
import { IAddresses, IFileNames, IJob, IUpgradeConfig, IVersions } from "../../../types";
import { addOrReplaceGuardInFile } from "../helpers";

export const compoundV3CometRewardsContractGuardJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  filenames: IFileNames,
  addresses: IAddresses,
) => {
  if (config.execute) {
    const ethers = hre.ethers;

    const compoundV3RewardsAddress = addresses.compoundV3?.rewards;

    if (!compoundV3RewardsAddress) return console.log("CompoundV3 reward contract address not found");

    const CompoundV3CometRewardsContractGuard = await ethers.getContractFactory("CompoundV3CometRewardsContractGuard");
    const compoundV3CometRewardsContractGuard = await CompoundV3CometRewardsContractGuard.deploy();
    await compoundV3CometRewardsContractGuard.deployed();
    const compoundV3CometRewardsContractGuardAddress = compoundV3CometRewardsContractGuard.address;
    console.log("CompoundV3CometRewardsContractGuard deployed at", compoundV3CometRewardsContractGuardAddress);

    versions[config.newTag].contracts.CompoundV3CometRewardsContractGuard = compoundV3CometRewardsContractGuardAddress;

    await tryVerify(
      hre,
      compoundV3CometRewardsContractGuardAddress,
      "contracts/guards/contractGuards/compound/CompoundV3CometRewardsContractGuard.sol:CompoundV3CometRewardsContractGuard",
      [],
    );

    const Governance = await hre.artifacts.readArtifact("Governance");

    await proposeTx(
      versions[config.oldTag].contracts.Governance,
      new ethers.utils.Interface(Governance.abi).encodeFunctionData("setContractGuard", [
        compoundV3RewardsAddress,
        compoundV3CometRewardsContractGuardAddress,
      ]),
      "setContractGuard for CompoundV3CometRewardsContractGuard",
      config,
      addresses,
    );

    const deployedGuard = {
      contractAddress: compoundV3RewardsAddress,
      guardName: "CompoundV3CometRewardsContractGuard",
      guardAddress: compoundV3CometRewardsContractGuardAddress,
      description: "CompoundV3 Comet Rewards ContractGuard",
    };

    await addOrReplaceGuardInFile(filenames.contractGuardsFileName, deployedGuard, "contractAddress");
  }
};
