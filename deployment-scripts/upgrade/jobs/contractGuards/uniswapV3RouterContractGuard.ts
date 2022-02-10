import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx, tryVerify } from "../../../Helpers";
import { addOrReplaceGuardInFile } from "../helpers";
import { IJob, IProposeTxProperties, IUpgradeConfig, IVersions } from "../../../types";

export const uniswapV3RouterContractGuard: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  // TODO: This optimally should not be mutated
  versions: IVersions,
  filenames: { contractGuardsFileName: string },
  addresses: { v3RouterAddresses?: string[] } & IProposeTxProperties,
) => {
  if (!addresses.v3RouterAddresses || !addresses.v3RouterAddresses.length) {
    console.warn("v2RouterAddresses not configured for v2RouterGuardJob: skipping.");
    return;
  }

  const ethers = hre.ethers;
  const Governance = await hre.artifacts.readArtifact("Governance");
  const governanceABI = new ethers.utils.Interface(Governance.abi);

  console.log("Will deploy uniswapv3routerguard");
  if (config.execute) {
    const UniswapV3RouterGuard = await ethers.getContractFactory("UniswapV3RouterGuard");
    const uniswapV3RouterGuard = await UniswapV3RouterGuard.deploy(10, 100); // set slippage 10%
    await uniswapV3RouterGuard.deployed();
    console.log("UniswapV3RouterGuard deployed at", uniswapV3RouterGuard.address);
    versions[config.newTag].contracts.UniswapV3RouterGuard = uniswapV3RouterGuard.address;

    await tryVerify(
      hre,
      uniswapV3RouterGuard.address,
      "contracts/guards/contractGuards/UniswapV3RouterGuard.sol:UniswapV3RouterGuard",
      [10, 100],
    );

    return Promise.all(
      addresses.v3RouterAddresses.map(async (routerAddress) => {
        const setContractGuardABI = governanceABI.encodeFunctionData("setContractGuard", [
          routerAddress,
          uniswapV3RouterGuard.address,
        ]);
        await proposeTx(
          versions[config.oldTag].contracts.Governance,
          setContractGuardABI,
          "setContractGuard for quickswapRouter",
          config,
          addresses,
        );

        const deployedGuard = {
          ContractAddress: routerAddress,
          GuardName: "UniswapV3RouterGuard",
          GuardAddress: uniswapV3RouterGuard.address,
          Description: "UniswapV3RouterGuard for " + routerAddress,
        };
        await addOrReplaceGuardInFile(filenames.contractGuardsFileName, deployedGuard, "ContractAddress");
      }),
    ).then(() => undefined);
  }
};
