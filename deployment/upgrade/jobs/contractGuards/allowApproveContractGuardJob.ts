import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx, tryVerify } from "../../../deploymentHelpers";
import { addOrReplaceGuardInFile } from "../helpers";
import { IJob, IUpgradeConfig, IVersions, IFileNames, IAddresses } from "../../../types";

export const allowApproveContractGuardJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  filenames: IFileNames,
  addresses: IAddresses,
) => {
  const ethers = hre.ethers;
  const Governance = await hre.artifacts.readArtifact("Governance");
  const governanceABI = new ethers.utils.Interface(Governance.abi);

  if (!addresses.allowApproveGuard) return console.warn("AllowApproveGuard deployment data is not provided: skipping.");

  console.log("Will deploy AllowApproveContractGuard");

  if (config.execute) {
    const AllowApproveContractGuard = await ethers.getContractFactory("AllowApproveContractGuard");
    const args: [string] = [addresses.allowApproveGuard.allowedSpender];
    const allowApproveContractGuard = await AllowApproveContractGuard.deploy(...args);
    await allowApproveContractGuard.deployed();

    const allowApproveContractGuardAddress = allowApproveContractGuard.address;
    console.log("AllowApproveContractGuard deployed at", allowApproveContractGuardAddress);
    versions[config.newTag].contracts.AllowApproveContractGuard = allowApproveContractGuardAddress;

    await tryVerify(
      hre,
      allowApproveContractGuardAddress,
      "contracts/guards/contractGuards/AllowApproveContractGuard.sol:AllowApproveContractGuard",
      args,
    );

    for (const to of addresses.allowApproveGuard.tokensToSetGuardTo) {
      await proposeTx(
        versions[config.oldTag].contracts.Governance,
        governanceABI.encodeFunctionData("setContractGuard", [to, allowApproveContractGuardAddress]),
        "setContractGuard for AllowApproveContractGuard",
        config,
        addresses,
      );

      await addOrReplaceGuardInFile(
        filenames.contractGuardsFileName,
        {
          contractAddress: to,
          guardName: "AllowApproveContractGuard",
          guardAddress: allowApproveContractGuardAddress,
          description: "Pool Token Swapper",
        },
        "contractAddress",
      );
    }
  }
};
