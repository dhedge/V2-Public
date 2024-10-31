import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx, tryVerify } from "../../../deploymentHelpers";
import { Address, IAddresses, IJob, IUpgradeConfig, IVersions } from "../../../types";
import { addOrReplaceGuardInFile } from "../helpers";

export const lyraOptionMarketWrapperContractGuardJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  filenames: { contractGuardsFileName: string },
  addresses: IAddresses,
) => {
  if (!versions[config.oldTag].contracts.PoolFactoryProxy) {
    console.warn("PoolFactoryProxy missing.. skipping.");
    return;
  }

  if (!addresses.lyra) {
    console.warn("Lyra addresses not configured for lyraOptionMarketWrapperContractGuard: skipping.");
    return;
  }

  const ethers = hre.ethers;

  const nftTrackerAddress = versions[config.oldTag].contracts.DhedgeNftTrackerStorageProxy;
  if (!nftTrackerAddress) {
    console.warn("nftTracker not deployed, skipping");
    return;
  }

  const Governance = await hre.artifacts.readArtifact("Governance");
  const governanceABI = new ethers.utils.Interface(Governance.abi);

  console.log("Will deploy LyraOptionMarketWrapperContractGuardRollups");
  if (config.execute) {
    const ContractGuard = await ethers.getContractFactory("LyraOptionMarketWrapperContractGuardRollups");
    const args: [Address, Address, number] = [addresses.lyra.lyraRegistry, nftTrackerAddress, 2];
    const contractGuard = await ContractGuard.deploy(...args);
    await contractGuard.deployed();
    console.log("contract guard deployed at", contractGuard.address);
    versions[config.newTag].contracts.LyraOptionMarketWrapperContractGuard = contractGuard.address;

    await tryVerify(
      hre,
      contractGuard.address,
      "contracts/guards/contractGuards/LyraOptionMarketWrapperContractGuardRollups.sol:LyraOptionMarketWrapperContractGuardRollups",
      args,
    );

    const optionMarketWrapper = await contractGuard.marketWrapper();

    const setContractGuardABI = governanceABI.encodeFunctionData("setContractGuard", [
      optionMarketWrapper,
      contractGuard.address,
    ]);

    await proposeTx(
      versions[config.oldTag].contracts.Governance,
      setContractGuardABI,
      "setContractGuard for LyraOptionMarketWrapperContractGuard",
      config,
      addresses,
    );

    const deployedGuard = {
      contractAddress: optionMarketWrapper,
      guardName: "LyraOptionMarketWrapperContractGuard",
      guardAddress: contractGuard.address,
      description: "Lyra OptionMarketWrapper Contract Guard",
    };
    await addOrReplaceGuardInFile(filenames.contractGuardsFileName, deployedGuard, "contractAddress");
  }
};
