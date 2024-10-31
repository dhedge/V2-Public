import { HardhatRuntimeEnvironment } from "hardhat/types";

import { proposeTx, tryVerify } from "../../../deploymentHelpers";
import { IDeployedContractGuard, IJob, IUpgradeConfig, IVersions, IFileNames, IAddresses } from "../../../types";
import { addOrReplaceGuardInFile } from "../helpers";

export const easySwapperV2ContractGuardJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  filenames: IFileNames,
  addresses: IAddresses,
) => {
  const easySwapperV2ProxyAddress = versions[config.newTag].contracts.EasySwapperV2Proxy;
  if (!easySwapperV2ProxyAddress) return console.warn("EasySwapperV2 could not be found: skipping.");

  const slippageaccumulatorAddress = versions[config.newTag].contracts.SlippageAccumulator;
  if (!slippageaccumulatorAddress) return console.warn("SlippageAccumulator could not be found: skipping.");

  const ethers = hre.ethers;

  console.log("Will deploy EasySwapperV2ContractGuard");

  if (config.execute) {
    const EasySwapperV2ContractGuard = await ethers.getContractFactory("EasySwapperV2ContractGuard");
    const easySwapperV2ContractGuard = await EasySwapperV2ContractGuard.deploy(slippageaccumulatorAddress);
    await easySwapperV2ContractGuard.deployed();
    const easySwapperV2ContractGuardAddress = easySwapperV2ContractGuard.address;

    console.log("EasySwapperV2ContractGuard deployed at: ", easySwapperV2ContractGuardAddress);

    versions[config.newTag].contracts.EasySwapperV2ContractGuard = easySwapperV2ContractGuardAddress;

    await tryVerify(
      hre,
      easySwapperV2ContractGuardAddress,
      "contracts/guards/contractGuards/EasySwapperV2ContractGuard.sol:EasySwapperV2ContractGuard",
      [slippageaccumulatorAddress],
    );

    const Governance = await hre.artifacts.readArtifact("Governance");
    await proposeTx(
      versions[config.oldTag].contracts.Governance,
      new ethers.utils.Interface(Governance.abi).encodeFunctionData("setContractGuard", [
        easySwapperV2ProxyAddress,
        easySwapperV2ContractGuardAddress,
      ]),
      "setContractGuard for EasySwapperV2",
      config,
      addresses,
    );

    const deployedGuard: IDeployedContractGuard = {
      contractAddress: easySwapperV2ProxyAddress,
      guardName: "EasySwapperV2ContractGuard",
      guardAddress: easySwapperV2ContractGuardAddress,
      description: "EasySwapperV2 - allows access to toros pools",
    };
    await addOrReplaceGuardInFile(filenames.contractGuardsFileName, deployedGuard, "contractAddress");
  }
};
