import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx, tryVerify } from "../../../deploymentHelpers";
import { addOrReplaceGuardInFile } from "../helpers";
import { IJob, IUpgradeConfig, IVersions, IDeployedContractGuard, IAddresses, IFileNames } from "../../../types";

export const uniswapV3RouterContractGuardJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  filenames: IFileNames,
  addresses: IAddresses,
) => {
  if (!addresses.uniV3.uniswapV3RouterAddress) {
    console.warn("uniswapV3RouterAddress not configured for uniswapV3RouterGuardJob: skipping.");
    return;
  }

  const ethers = hre.ethers;
  const Governance = await hre.artifacts.readArtifact("Governance");
  const governanceABI = new ethers.utils.Interface(Governance.abi);

  console.log("Will deploy uniswapv3routerguard");
  if (config.execute) {
    const UniswapV3RouterGuard = await ethers.getContractFactory("UniswapV3RouterGuard");
    const slippageaccumulatorAddress = versions[config.oldTag].contracts.SlippageAccumulator;
    if (!slippageaccumulatorAddress) {
      console.warn("SlippageAccumulator could not be found: skipping.");
      return;
    }
    const args: [string] = [slippageaccumulatorAddress];
    const uniswapV3RouterGuard = await UniswapV3RouterGuard.deploy(...args);
    await uniswapV3RouterGuard.deployed();
    console.log("UniswapV3RouterGuard deployed at", uniswapV3RouterGuard.address);
    versions[config.newTag].contracts.UniswapV3RouterGuard = uniswapV3RouterGuard.address;

    await tryVerify(
      hre,
      uniswapV3RouterGuard.address,
      "contracts/guards/contractGuards/uniswapV3/UniswapV3RouterGuard.sol:UniswapV3RouterGuard",
      args,
    );

    const setContractGuardABI = governanceABI.encodeFunctionData("setContractGuard", [
      addresses.uniV3.uniswapV3RouterAddress,
      uniswapV3RouterGuard.address,
    ]);
    await proposeTx(
      versions[config.oldTag].contracts.Governance,
      setContractGuardABI,
      "setContractGuard for uniswapV3Router",
      config,
      addresses,
    );

    const deployedGuard: IDeployedContractGuard = {
      contractAddress: addresses.uniV3.uniswapV3RouterAddress,
      guardName: "UniswapV3RouterGuard",
      guardAddress: uniswapV3RouterGuard.address,
      description: "Uniswap V3 Router guard",
    };
    await addOrReplaceGuardInFile(filenames.contractGuardsFileName, deployedGuard, "contractAddress");
  }
};
