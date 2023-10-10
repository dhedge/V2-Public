import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx } from "../../../deploymentHelpers";
import { addOrReplaceGuardInFile } from "../helpers";
import { IAddresses, IJob, IUpgradeConfig, IVersions } from "../../../types";

export const lyraMarketsContractGuardJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  filenames: { contractGuardsFileName: string },
  addresses: IAddresses,
) => {
  if (!versions[config.oldTag].contracts.Governance) {
    console.warn("Governance not does not exist in versions: skipping.");
    return;
  }

  const ethers = hre.ethers;
  const Governance = await hre.artifacts.readArtifact("Governance");
  const governanceABI = new ethers.utils.Interface(Governance.abi);
  const governance = await ethers.getContractAt("Governance", versions[config.oldTag].contracts.Governance);
  const dhedgeOptionMarketWrapperForLyraAddress = versions[config.oldTag].contracts.DhedgeOptionMarketWrapperForLyra;

  console.log("Will add lyra market contracts");
  const erc721guard = versions[config.oldTag].contracts.ERC721ContractGuard;
  if (!erc721guard) {
    console.warn("ERC721ContractGuard not does not exist in versions: skipping.");
    return;
  }

  if (!dhedgeOptionMarketWrapperForLyraAddress) {
    console.warn("DhedgeOptionMarketWrapperForLyra not does not exist in versions: skipping.");
    return;
  }

  if (!addresses.lyra) {
    console.warn("Lyra addresses not configured for lyraOptionMarketWrapperContractGuard: skipping.");
    return;
  }

  if (config.execute) {
    const lyraRegistry = await ethers.getContractAt(
      "contracts/interfaces/lyra/ILyraRegistry.sol:ILyraRegistry",
      addresses.lyra?.lyraRegistry,
    );

    let index = 0;
    let market = await lyraRegistry.optionMarkets(index);
    while (market != ethers.constants.AddressZero) {
      const { optionToken } = await lyraRegistry.getMarketAddresses(market);
      console.log("Checking configuration for lyra option token", optionToken);

      // Configure a contractGuard for each market if it doesn't exist or the erc721Guard has changed
      if ((await governance.contractGuards(optionToken)) !== erc721guard) {
        console.log("Configuring lyra option token", optionToken);
        const setContractGuardABI = governanceABI.encodeFunctionData("setContractGuard", [optionToken, erc721guard]);

        await proposeTx(
          versions[config.oldTag].contracts.Governance,
          setContractGuardABI,
          "setContractGuard ERC721 Guard for lyraOptionToken",
          config,
          addresses,
        );

        const deployedGuard = {
          contractAddress: optionToken,
          guardName: "LyraOptionERC721ContractGuard",
          guardAddress: erc721guard,
          description: "Lyra Option ERC721 Contract Guard",
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
