import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx, tryVerify } from "../../../deploymentHelpers";
import { addOrReplaceGuardInFile } from "../helpers";
import { IJob, IUpgradeConfig, IVersions, IFileNames, IAddresses } from "../../../types";

export const poolTokenSwapperGuardJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  filenames: IFileNames,
  addresses: IAddresses,
) => {
  const poolTokenSwapperProxyAddress = versions[config.oldTag].contracts.PoolTokenSwapperProxy;

  if (!poolTokenSwapperProxyAddress) {
    return console.warn("PoolTokenSwapper is not deployed: skipping.");
  }

  const ethers = hre.ethers;
  const Governance = await hre.artifacts.readArtifact("Governance");
  const governanceABI = new ethers.utils.Interface(Governance.abi);

  console.log("Will deploy PoolTokenSwapperGuard");

  if (config.execute) {
    const PoolTokenSwapperGuard = await ethers.getContractFactory("PoolTokenSwapperGuard");
    const poolTokenSwapperGuard = await PoolTokenSwapperGuard.deploy();
    await poolTokenSwapperGuard.deployed();

    const poolTokenSwapperGuardAddress = poolTokenSwapperGuard.address;
    console.log("PoolTokenSwapperGuard deployed at", poolTokenSwapperGuardAddress);
    versions[config.newTag].contracts.PoolTokenSwapperGuard = poolTokenSwapperGuardAddress;

    await tryVerify(
      hre,
      poolTokenSwapperGuardAddress,
      "contracts/guards/contractGuards/PoolTokenSwapperGuard.sol:PoolTokenSwapperGuard",
      [],
    );

    await proposeTx(
      versions[config.oldTag].contracts.Governance,
      governanceABI.encodeFunctionData("setContractGuard", [
        poolTokenSwapperProxyAddress,
        poolTokenSwapperGuardAddress,
      ]),
      "setContractGuard for PoolTokenSwapperGuard",
      config,
      addresses,
    );

    await addOrReplaceGuardInFile(
      filenames.contractGuardsFileName,
      {
        contractAddress: poolTokenSwapperProxyAddress,
        guardName: "PoolTokenSwapperGuard",
        guardAddress: poolTokenSwapperGuardAddress,
        description: "Pool Token Swapper",
      },
      "contractAddress",
    );
  }
};
