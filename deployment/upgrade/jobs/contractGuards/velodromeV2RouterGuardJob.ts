import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx, tryVerify } from "../../../deploymentHelpers";
import { IAddresses, IFileNames, IJob, IUpgradeConfig, IVersions } from "../../../types";
import { addOrReplaceGuardInFile } from "../helpers";

export const velodromeV2RouterGuardJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  filenames: IFileNames,
  addresses: IAddresses,
) => {
  const ethers = hre.ethers;
  const Governance = await hre.artifacts.readArtifact("Governance");
  const governanceABI = new ethers.utils.Interface(Governance.abi);
  const velodromeV2RouterAddress = addresses.velodrome?.routerV2;

  if (!velodromeV2RouterAddress) {
    return console.warn("Velodrome V2 Router address not configured for VelodromeV2RouterGuard. Skipping.");
  }

  console.log("Will deploy VelodromeV2RouterGuard");

  if (config.execute) {
    const VelodromeV2RouterGuard = await ethers.getContractFactory("VelodromeV2RouterGuard");
    const velodromeV2RouterGuard = await VelodromeV2RouterGuard.deploy();
    await velodromeV2RouterGuard.deployed();
    const address = velodromeV2RouterGuard.address;

    console.log("VelodromeV2RouterGuard deployed at", address);

    await tryVerify(
      hre,
      address,
      "contracts/guards/contractGuards/velodrome/VelodromeV2RouterGuard.sol:VelodromeV2RouterGuard",
      [],
    );

    versions[config.newTag].contracts.VelodromeV2RouterGuard = address;

    const setContractGuardABI = governanceABI.encodeFunctionData("setContractGuard", [
      velodromeV2RouterAddress,
      address,
    ]);
    await proposeTx(
      versions[config.oldTag].contracts.Governance,
      setContractGuardABI,
      "setContractGuard for VelodromeV2RouterGuard",
      config,
      addresses,
    );

    const deployedGuard = {
      contractAddress: velodromeV2RouterAddress,
      guardName: "VelodromeV2RouterGuard",
      guardAddress: address,
      description: "Velodrome V2 Router Guard",
    };
    await addOrReplaceGuardInFile(filenames.contractGuardsFileName, deployedGuard, "contractAddress");
  }
};
