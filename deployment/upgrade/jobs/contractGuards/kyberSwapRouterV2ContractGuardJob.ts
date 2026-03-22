import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx, tryVerify } from "../../../deploymentHelpers";
import { addOrReplaceGuardInFile } from "../helpers";
import { IJob, IUpgradeConfig, IVersions, IFileNames, IAddresses, Address } from "../../../types";

export const kyberSwapRouterV2ContractGuardJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  filenames: IFileNames,
  addresses: IAddresses,
) => {
  const kyberSwapRouterV2 = addresses.kyberSwap?.routerV2;

  if (!kyberSwapRouterV2) {
    return console.warn("kyberSwapRouterV2 not configured: skipping.");
  }

  const ethers = hre.ethers;
  const Governance = await hre.artifacts.readArtifact("Governance");

  console.log("Will deploy KyberSwapRouterV2ContractGuard");

  if (config.execute) {
    const slippageAccumulatorAddress = versions[config.oldTag].contracts.SlippageAccumulator;

    if (!slippageAccumulatorAddress) {
      return console.warn("SlippageAccumulator could not be found: skipping.");
    }

    const KyberSwapRouterV2ContractGuard = await ethers.getContractFactory("KyberSwapRouterV2ContractGuard");
    const args: [Address] = [slippageAccumulatorAddress];
    const kyberSwapRouterV2ContractGuard = await KyberSwapRouterV2ContractGuard.deploy(...args);
    await kyberSwapRouterV2ContractGuard.deployed();
    const kyberSwapRouterV2ContractGuardAddress = kyberSwapRouterV2ContractGuard.address;

    console.log("KyberSwapRouterV2ContractGuard deployed at", kyberSwapRouterV2ContractGuardAddress);

    versions[config.newTag].contracts.KyberSwapRouterV2ContractGuard = kyberSwapRouterV2ContractGuardAddress;

    await tryVerify(
      hre,
      kyberSwapRouterV2ContractGuardAddress,
      "contracts/guards/contractGuards/kyberSwap/KyberSwapRouterV2ContractGuard.sol:KyberSwapRouterV2ContractGuard",
      args,
    );

    const setContractGuardABI = new ethers.utils.Interface(Governance.abi).encodeFunctionData("setContractGuard", [
      kyberSwapRouterV2,
      kyberSwapRouterV2ContractGuardAddress,
    ]);

    await proposeTx(
      versions[config.oldTag].contracts.Governance,
      setContractGuardABI,
      "setContractGuard for KyberSwapRouterV2ContractGuard",
      config,
      addresses,
    );

    const deployedGuard = {
      contractAddress: kyberSwapRouterV2,
      guardName: "KyberSwapRouterV2ContractGuard",
      guardAddress: kyberSwapRouterV2ContractGuardAddress,
      description: "KyberSwap V2 Router",
    };
    await addOrReplaceGuardInFile(filenames.contractGuardsFileName, deployedGuard, "contractAddress");
  }
};
