import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx, tryVerify } from "../../../deploymentHelpers";
import { addOrReplaceGuardInFile } from "../helpers";
import { IJob, IUpgradeConfig, IVersions, IFileNames, IAddresses } from "../../../types";

export const ondoGMSwapContractGuardJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  filenames: IFileNames,
  addresses: IAddresses,
) => {
  const ondoGMSwapProxy = versions[config.oldTag].contracts.OndoGMSwapProxy;
  if (!ondoGMSwapProxy) return console.warn("OndoGMSwapProxy not found: skipping.");

  const guardConfig = addresses.ondo?.ondoGMSwapContractGuard;
  if (!guardConfig) return console.warn("ondo.ondoGMSwapContractGuard not configured: skipping.");

  const ethers = hre.ethers;
  const Governance = await hre.artifacts.readArtifact("Governance");

  console.log("Will deploy OndoGMSwapContractGuard");

  if (config.execute) {
    const slippageAccumulatorAddress = versions[config.oldTag].contracts.SlippageAccumulator;
    if (!slippageAccumulatorAddress) return console.warn("SlippageAccumulator could not be found: skipping.");

    const attestationOracleProxy = versions[config.oldTag].contracts.OndoAttestationOracleProxy;
    if (!attestationOracleProxy) return console.warn("OndoAttestationOracleProxy not found: skipping.");

    const OndoGMSwapContractGuard = await ethers.getContractFactory("OndoGMSwapContractGuard");
    const args = [slippageAccumulatorAddress, guardConfig.maxSlippagePerSwapBps, attestationOracleProxy] as const;
    const ondoGMSwapContractGuard = await OndoGMSwapContractGuard.deploy(...args);
    await ondoGMSwapContractGuard.deployed();
    const guardAddress = ondoGMSwapContractGuard.address;

    console.log("OndoGMSwapContractGuard deployed at", guardAddress);

    versions[config.newTag].contracts.OndoGMSwapContractGuard = guardAddress;

    await tryVerify(
      hre,
      guardAddress,
      "contracts/guards/contractGuards/ondo/OndoGMSwapContractGuard.sol:OndoGMSwapContractGuard",
      [...args],
    );

    const setContractGuardABI = new ethers.utils.Interface(Governance.abi).encodeFunctionData("setContractGuard", [
      ondoGMSwapProxy,
      guardAddress,
    ]);

    await proposeTx(
      versions[config.oldTag].contracts.Governance,
      setContractGuardABI,
      "setContractGuard for OndoGMSwapContractGuard",
      config,
      addresses,
    );

    const deployedGuard = {
      contractAddress: ondoGMSwapProxy,
      guardName: "OndoGMSwapContractGuard",
      guardAddress: guardAddress,
      description: "Ondo GM Swap",
    };
    await addOrReplaceGuardInFile(filenames.contractGuardsFileName, deployedGuard, "contractAddress");
  }
};
