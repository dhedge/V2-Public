import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx, tryVerify } from "../../../deploymentHelpers";
import { addOrReplaceGuardInFile } from "../helpers";
import { IAddresses, IFileNames, IJob, IUpgradeConfig, IVersions } from "../../../types";

export const synthRedeemerContractGuardJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  filenames: IFileNames,
  addresses: IAddresses,
) => {
  if (!addresses.assets.susd || !addresses.synthRedeemer) {
    return console.warn(
      "sUSD address or SynthRedeemer address not configured for synthRedeemerContractGuardJob: aborting",
    );
  }

  console.log("Will deploy synthRedeemerContractGuard");
  if (config.execute) {
    const SynthRedeemerFactory = await hre.ethers.getContractFactory("SynthRedeemerContractGuard");
    const args: [string] = [addresses.assets.susd];
    const synthRedeemerContractGuard = await SynthRedeemerFactory.deploy(...args);
    await synthRedeemerContractGuard.deployed();
    await synthRedeemerContractGuard.deployTransaction.wait(5);
    console.log("synthRedeemerContractGuard deployed at", synthRedeemerContractGuard.address);

    await tryVerify(
      hre,
      synthRedeemerContractGuard.address,
      "contracts/guards/contractGuards/SynthRedeemerContractGuard.sol:SynthRedeemerContractGuard",
      args,
    );

    const GovernanceArtifact = await hre.artifacts.readArtifact("Governance");
    const governanceABI = new hre.ethers.utils.Interface(GovernanceArtifact.abi);
    const setContractGuardTxData = governanceABI.encodeFunctionData("setContractGuard", [
      addresses.synthRedeemer,
      synthRedeemerContractGuard.address,
    ]);

    await proposeTx(
      versions[config.oldTag].contracts.Governance,
      setContractGuardTxData,
      "setContractGuard for SynthRedeemer",
      config,
      addresses,
    );

    await addOrReplaceGuardInFile(
      filenames.contractGuardsFileName,
      {
        contractAddress: addresses.synthRedeemer,
        guardName: "SynthRedeemerContractGuard",
        guardAddress: synthRedeemerContractGuard.address,
        description: "Synth Redeemer guard",
      },
      "contractAddress",
    );

    versions[config.newTag].contracts.SynthRedeemerContractGuard = synthRedeemerContractGuard.address;
  }
};
