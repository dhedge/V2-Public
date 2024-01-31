import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx, tryVerify } from "../../../deploymentHelpers";
import { IAddresses, IFileNames, IJob, IUpgradeConfig, IVersions } from "../../../types";
import { addOrReplaceGuardInFile } from "../helpers";

export const ramsesRouterGuardJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  filenames: IFileNames,
  addresses: IAddresses,
) => {
  console.log("Will deploy RamsesRouterContractGuard");
  const ramsesRouter = addresses.ramses?.router;

  if (!ramsesRouter) {
    return console.warn("RAMSES router address not configured for RamsesRouterContractGuard. skipping.");
  }

  if (config.execute) {
    const ethers = hre.ethers;

    const RamsesRouterContractGuard = await ethers.getContractFactory("RamsesRouterContractGuard");
    const ramsesRouterContractGuard = await RamsesRouterContractGuard.deploy();
    await ramsesRouterContractGuard.deployed();
    const ramsesRouterContractGuardAddress = ramsesRouterContractGuard.address;
    console.log("RamsesRouterContractGuard deployed at", ramsesRouterContractGuardAddress);

    versions[config.newTag].contracts.RamsesRouterContractGuard = ramsesRouterContractGuardAddress;

    await tryVerify(
      hre,
      ramsesRouterContractGuardAddress,
      "contracts/guards/contractGuards/ramses/RamsesRouterContractGuard.sol:RamsesRouterContractGuard",
      [],
    );

    const Governance = await hre.artifacts.readArtifact("Governance");
    const governanceABI = new ethers.utils.Interface(Governance.abi);
    const setContractGuardTxData = governanceABI.encodeFunctionData("setContractGuard", [
      ramsesRouter,
      ramsesRouterContractGuardAddress,
    ]);

    await proposeTx(
      versions[config.oldTag].contracts.Governance,
      setContractGuardTxData,
      "setContractGuard for RamsesRouterContractGuard",
      config,
      addresses,
    );

    const deployedGuard = {
      contractAddress: ramsesRouter,
      guardName: "RamsesRouterContractGuard",
      guardAddress: ramsesRouterContractGuardAddress,
      description: "Ramses Router Guard",
    };

    await addOrReplaceGuardInFile(filenames.contractGuardsFileName, deployedGuard, "contractAddress");
  }
};
