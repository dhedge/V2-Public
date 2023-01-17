import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx, tryVerify } from "../../../Helpers";
import { IAddresses, IJob, IUpgradeConfig, IVersions } from "../../../types";
import { addOrReplaceGuardInFile } from "../helpers";

/***
 * Deploys and sets the LyraOptionMarketWrapperContractGuard
 */
export const lyraOptionMarketWrapperContractGuardJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  // TODO: This optimally should not be mutated
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
  if (!addresses.synthetixAddressResolverAddress) {
    console.warn("synthetixAddressResolverAddress not configured for lyraOptionMarketWrapperContractGuard: skipping.");
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
    const contractGuard = await ContractGuard.deploy(
      addresses.lyra.optionMarketWrapper,
      addresses.lyra.optionMarketViewer,
      nftTrackerAddress,
      2,
    );
    await contractGuard.deployed();
    console.log("contract guard deployed at", contractGuard.address);
    versions[config.newTag].contracts.LyraOptionMarketWrapperContractGuard = contractGuard.address;

    await tryVerify(
      hre,
      contractGuard.address,
      "contracts/guards/contractGuards/LyraOptionMarketWrapperContractGuardRollups.sol:LyraOptionMarketWrapperContractGuardRollups",
      [addresses.lyra.optionMarketWrapper, addresses.lyra.optionMarketViewer, nftTrackerAddress, 2],
    );

    const setContractGuardABI = governanceABI.encodeFunctionData("setContractGuard", [
      addresses.lyra.optionMarketWrapper,
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
      contractAddress: addresses.lyra.optionMarketWrapper,
      guardName: "LyraOptionMarketWrapperContractGuard",
      guardAddress: contractGuard.address,
      description: "Lyra OptionMarketWrapper Contract Guard",
    };
    await addOrReplaceGuardInFile(filenames.contractGuardsFileName, deployedGuard, "contractAddress");
  }
};
