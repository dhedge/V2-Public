import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx, tryVerify } from "../../../deploymentHelpers";
import { IAddresses, IFileNames, IJob, IUpgradeConfig, IVersions } from "../../../types";
import { addOrReplaceGuardInFile } from "../helpers";

export const velodromeRouterGuardJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  filenames: IFileNames,
  addresses: IAddresses,
) => {
  const ethers = hre.ethers;
  const Governance = await hre.artifacts.readArtifact("Governance");
  const governanceABI = new ethers.utils.Interface(Governance.abi);

  if (!addresses.velodrome?.router) {
    console.warn("Velodrome router address not configured for VelodromeRouterGuard skipping.");
    return;
  }

  console.log("Will deploy velodromerouterguard");
  if (config.execute) {
    const VelodromeRouterGuard = await ethers.getContractFactory("VelodromeRouterGuard");
    const velodromeRouterGuard = await VelodromeRouterGuard.deploy();
    await velodromeRouterGuard.deployed();
    console.log("VelodromeRouterGuard deployed at", velodromeRouterGuard.address);
    versions[config.newTag].contracts.VelodromeRouterGuard = velodromeRouterGuard.address;

    await tryVerify(
      hre,
      velodromeRouterGuard.address,
      "contracts/guards/contractGuards/velodrome/VelodromeRouterGuard.sol:VelodromeRouterGuard",
      [],
    );

    const setContractGuardABI = governanceABI.encodeFunctionData("setContractGuard", [
      addresses.velodrome.router,
      velodromeRouterGuard.address,
    ]);
    await proposeTx(
      versions[config.oldTag].contracts.Governance,
      setContractGuardABI,
      "setContractGuard for VelodromeRouterGuard",
      config,
      addresses,
    );
    const deployedGuard = {
      contractAddress: addresses.velodrome.router,
      guardName: "VelodromeRouterGuard",
      guardAddress: velodromeRouterGuard.address,
      description: "Velodrome Router Guard",
    };
    await addOrReplaceGuardInFile(filenames.contractGuardsFileName, deployedGuard, "contractAddress");
  }
};
