import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx, tryVerify } from "../../../Helpers";
import { addOrReplaceGuardInFile } from "../helpers";
import { IJob, IProposeTxProperties, IUpgradeConfig, IVersions } from "../../../types";

export const sushiMiniChefV2ContractGuardJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  // TODO: This optimally should not be mutated
  versions: IVersions,
  filenames: { contractGuardsFileName: string },
  addresses: {
    protocolDaoAddress: string;
    sushiMiniChefV2Address?: string;
    sushiTokenAddress?: string;
    wmaticTokenAddress?: string;
  } & IProposeTxProperties,
) => {
  if (!addresses.sushiMiniChefV2Address) {
    console.warn("sushiMiniChefV2Address not configured for sushiMiniChefV2GuardGuardJob: skipping.");
    return;
  }
  //
  // this Job needs to be refactored to be more generic
  //
  if (!addresses.sushiTokenAddress) {
    console.warn("sushiTokenAddress not configured for sushiMiniChefV2GuardGuardJob: skipping.");
    return;
  }
  if (!addresses.wmaticTokenAddress) {
    console.warn("wmaticTokenAddress not configured for sushiMiniChefV2GuardGuardJob: skipping.");
    return;
  }

  const ethers = hre.ethers;
  const Governance = await hre.artifacts.readArtifact("Governance");
  const governanceABI = new ethers.utils.Interface(Governance.abi);

  console.log("Will deploy sushiminichefv2guard");
  if (config.execute) {
    const SushiMiniChefV2Guard = await ethers.getContractFactory("SushiMiniChefV2Guard");
    const sushiMiniChefV2Guard = await SushiMiniChefV2Guard.deploy([
      addresses.sushiTokenAddress,
      addresses.wmaticTokenAddress,
    ]);
    await sushiMiniChefV2Guard.deployed();
    console.log("SushiMiniChefV2Guard deployed at", sushiMiniChefV2Guard.address);
    versions[config.newTag].contracts.SushiMiniChefV2Guard = sushiMiniChefV2Guard.address;

    await tryVerify(
      hre,
      sushiMiniChefV2Guard.address,
      "contracts/guards/contractGuards/SushiMiniChefV2Guard.sol:SushiMiniChefV2Guard",
      [[addresses.sushiTokenAddress, addresses.wmaticTokenAddress]],
    );

    const setContractGuardABI = governanceABI.encodeFunctionData("setContractGuard", [
      addresses.sushiMiniChefV2Address,
      sushiMiniChefV2Guard.address,
    ]);
    await proposeTx(
      versions[config.oldTag].contracts.Governance,
      setContractGuardABI,
      "setContractGuard for sushiMiniChefV2Guard",
      config,
      addresses,
    );
    const deployedGuard = {
      contractAddress: addresses.sushiMiniChefV2Address,
      guardName: "SushiMiniChefV2Guard",
      guardAddress: sushiMiniChefV2Guard.address,
      description: "Sushi rewards contract",
    };
    await addOrReplaceGuardInFile(filenames.contractGuardsFileName, deployedGuard, "contractAddress");
  }
};
