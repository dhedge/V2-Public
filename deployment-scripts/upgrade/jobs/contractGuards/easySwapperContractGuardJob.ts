import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx, tryVerify } from "../../../Helpers";
import { addOrReplaceGuardInFile } from "../helpers";
import { IJob, IProposeTxProperties, IUpgradeConfig, IVersions } from "../../../types";

export const easySwapperContractGuardJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  // TODO: This should be types and optimally should not be mutated
  versions: IVersions,
  filenames: { contractGuardsFileName: string },
  addresses: { dhedgeEasySwapperAddress?: string } & IProposeTxProperties,
) => {
  if (!addresses.dhedgeEasySwapperAddress) {
    console.warn("dhedgeEasySwapperAddress not configured for easySwapperContractGuardJob: skipping.");
    return;
  }

  const ethers = hre.ethers;
  const Governance = await hre.artifacts.readArtifact("Governance");
  const governanceABI = new ethers.utils.Interface(Governance.abi);

  console.log("Will deploy easyswapperguard");
  if (config.execute) {
    const EasySwapperGuard = await ethers.getContractFactory("EasySwapperGuard");
    const easySwapperGuard = await EasySwapperGuard.deploy();
    await easySwapperGuard.deployed();
    console.log("EasySwapperGuard deployed at", easySwapperGuard.address);
    versions[config.newTag].contracts.EasySwapperGuard = easySwapperGuard.address;

    await tryVerify(hre, easySwapperGuard.address, "contracts/guards/EasySwapperGuard.sol:EasySwapperGuard", []);

    const setContractGuardABI = governanceABI.encodeFunctionData("setContractGuard", [
      addresses.dhedgeEasySwapperAddress,
      easySwapperGuard.address,
    ]);
    await proposeTx(
      versions[config.oldTag].contracts.Governance,
      setContractGuardABI,
      "setContractGuard for easySwapperGuard",
      config,
      addresses,
    );

    const deployedGuard = {
      ContractAddress: addresses.dhedgeEasySwapperAddress,
      GuardName: "EasySwapperGuard",
      GuardAddress: easySwapperGuard.address,
      Description: "Dhedge EasySwapper - allows access to toros pools",
    };
    await addOrReplaceGuardInFile(filenames.contractGuardsFileName, deployedGuard, "ContractAddress");
  }
};
