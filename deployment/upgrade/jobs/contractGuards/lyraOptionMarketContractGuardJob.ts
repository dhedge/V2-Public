import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx, tryVerify } from "../../../deploymentHelpers";
import { Address, IAddresses, IFileNames, IJob, IUpgradeConfig, IVersions } from "../../../types";
import { addOrReplaceGuardInFile } from "../helpers";

/***
 * Deploys and sets the LyraOptionMarketContractGuard
 *
 * NOTE: All OptionMarket positions are aggregated into the OptionMarketWrapper Asset
 * There are no individual OptionMarket assets
 */
export const lyraOptionMarketContractGuardJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  filenames: IFileNames,
  addresses: IAddresses,
) => {
  if (!versions[config.oldTag].contracts.PoolFactoryProxy) {
    console.warn("PoolFactoryProxy missing.. skipping.");
    return;
  }

  if (!addresses.lyra) {
    console.warn("Lyra addresses not configured for lyraOptionMarketContractGuard: skipping.");
    return;
  }

  const ethers = hre.ethers;

  const nftTrackerAddress = versions[config.oldTag].contracts.DhedgeNftTrackerStorageProxy;
  if (!nftTrackerAddress) {
    console.warn("nftTracker not deployed, skipping");
    return;
  }

  console.log("Will deploy LyraOptionMarketContractGuard");
  if (config.execute) {
    const Governance = await hre.artifacts.readArtifact("Governance");
    const governanceABI = new ethers.utils.Interface(Governance.abi);
    const governance = await ethers.getContractAt("Governance", versions[config.oldTag].contracts.Governance);
    const ContractGuard = await ethers.getContractFactory("LyraOptionMarketContractGuard");
    const args: [Address, Address, number] = [addresses.lyra.lyraRegistry, nftTrackerAddress, 2];
    const contractGuard = await ContractGuard.deploy(...args);
    await contractGuard.deployed();
    console.log("contract guard deployed at", contractGuard.address);
    await tryVerify(
      hre,
      contractGuard.address,
      "contracts/guards/contractGuards/LyraOptionMarketContractGuard.sol:LyraOptionMarketContractGuard",
      args,
    );

    versions[config.newTag].contracts.LyraOptionMarketContractGuard = contractGuard.address;
    ///

    const lyraRegistry = await ethers.getContractAt(
      "contracts/interfaces/lyra/ILyraRegistry.sol:ILyraRegistry",
      addresses.lyra?.lyraRegistry,
    );

    let index = 0;
    let market = await lyraRegistry.optionMarkets(index);
    while (market != ethers.constants.AddressZero) {
      const { optionMarket } = await lyraRegistry.getMarketAddresses(market);
      console.log("Checking configuration for lyra option market", optionMarket);

      // Configure a contractGuard for each market if it doesn't exist or the erc721Guard has changed
      if ((await governance.contractGuards(optionMarket)) !== contractGuard.address) {
        console.log("Configuring lyra option token", optionMarket);
        const setContractGuardABI = governanceABI.encodeFunctionData("setContractGuard", [
          optionMarket,
          contractGuard.address,
        ]);

        await proposeTx(
          versions[config.oldTag].contracts.Governance,
          setContractGuardABI,
          "setContractGuard LyraOptionMarketContractGuard for lyraOptionMarket",
          config,
          addresses,
        );

        const deployedGuard = {
          contractAddress: optionMarket,
          guardName: "LyraOptionMarketContractGuard",
          guardAddress: contractGuard.address,
          description: "Lyra Option Market Contract Guard",
        };
        await addOrReplaceGuardInFile(filenames.contractGuardsFileName, deployedGuard, "contractAddress");
      }
      index++;
      try {
        market = await lyraRegistry.optionMarkets(index);
      } catch {
        market = ethers.constants.AddressZero;
      }
    }
  }
};
