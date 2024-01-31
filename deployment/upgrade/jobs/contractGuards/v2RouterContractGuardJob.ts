import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx, tryVerify } from "../../../deploymentHelpers";
import { addOrReplaceGuardInFile } from "../helpers";
import { IJob, IAddresses, IUpgradeConfig, IVersions } from "../../../types";

export const v2RouterContractGuardJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  // TODO: This optimally should not be mutated
  versions: IVersions,
  filenames: { contractGuardsFileName: string },
  addresses: IAddresses,
) => {
  if (!addresses.v2RouterAddresses) {
    console.warn("v2RouterAddresses not configured for v2RouterGuardJob: skipping.");
    return;
  }

  const ethers = hre.ethers;
  const Governance = await hre.artifacts.readArtifact("Governance");
  const governanceABI = new ethers.utils.Interface(Governance.abi);

  console.log("Will deploy uniswapv2routerguard");
  if (config.execute) {
    const UniswapV2RouterGuard = await ethers.getContractFactory("UniswapV2RouterGuard");
    const slippageaccumulatorAddress = versions[config.oldTag].contracts.SlippageAccumulator;
    if (!slippageaccumulatorAddress) {
      console.warn("SlippageAccumulator could not be found: skipping.");
      return;
    }
    const args: [string] = [slippageaccumulatorAddress];
    const uniswapV2RouterGuard = await UniswapV2RouterGuard.deploy(...args);
    await uniswapV2RouterGuard.deployed();
    console.log("UniswapV2RouterGuard deployed at", uniswapV2RouterGuard.address);
    versions[config.newTag].contracts.UniswapV2RouterGuard = uniswapV2RouterGuard.address;

    await tryVerify(
      hre,
      uniswapV2RouterGuard.address,
      "contracts/guards/contractGuards/UniswapV2RouterGuard.sol:UniswapV2RouterGuard",
      args,
    );

    await Promise.all(
      addresses.v2RouterAddresses.map(async (routerAddress) => {
        const setContractGuardABI = governanceABI.encodeFunctionData("setContractGuard", [
          routerAddress,
          uniswapV2RouterGuard.address,
        ]);
        await proposeTx(
          versions[config.oldTag].contracts.Governance,
          setContractGuardABI,
          "setContractGuard for quickswapRouter",
          config,
          addresses,
        );

        const deployedGuard = {
          contractAddress: routerAddress,
          guardName: "UniswapV2RouterGuard",
          guardAddress: uniswapV2RouterGuard.address,
          description: "UniswapV2RouterGuard for " + routerAddress,
        };
        await addOrReplaceGuardInFile(filenames.contractGuardsFileName, deployedGuard, "contractAddress");
      }),
    );
  }
};
