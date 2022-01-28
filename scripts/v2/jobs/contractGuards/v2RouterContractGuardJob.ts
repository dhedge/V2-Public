import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx, tryVerify } from "../../../Helpers";
import { addOrReplaceGuardInFile } from "../helpers";
import { IJob, IUpgradeConfig } from "../../types";

export const v2RouterContractGuardJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  // TODO: This should be types and optimally should not be mutated
  versions: any,
  filenames: { contractGuardsFileName: string },
  addresses: { protocolDaoAddress: string; v2RouterAddresses?: string[] },
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
    const uniswapV2RouterGuard = await UniswapV2RouterGuard.deploy(10, 100); // set slippage 10%
    await uniswapV2RouterGuard.deployed();
    console.log("UniswapV2RouterGuard deployed at", uniswapV2RouterGuard.address);
    versions[config.newTag].contracts.UniswapV2RouterGuard = uniswapV2RouterGuard.address;

    await tryVerify(
      hre,
      uniswapV2RouterGuard.address,
      "contracts/guards/contractGuards/UniswapV2RouterGuard.sol:UniswapV2RouterGuard",
      [10, 100],
    );

    await uniswapV2RouterGuard.transferOwnership(addresses.protocolDaoAddress);

    return Promise.all(
      addresses.v2RouterAddresses.map(async (routerAddress) => {
        const setContractGuardABI = governanceABI.encodeFunctionData("setContractGuard", [
          routerAddress,
          uniswapV2RouterGuard.address,
        ]);
        await proposeTx(
          versions[config.oldTag].contracts.Governance,
          setContractGuardABI,
          "setContractGuard for quickswapRouter",
          config.execute,
          config.restartnonce,
        );

        const deployedGuard = {
          ContractAddress: routerAddress,
          GuardName: "UniswapV2RouterGuard",
          GuardAddress: uniswapV2RouterGuard.address,
          Description: "UniswapV2RouterGuard for " + routerAddress,
        };
        await addOrReplaceGuardInFile(filenames.contractGuardsFileName, deployedGuard, "ContractAddress");
      }),
    ).then(() => undefined);
  }
};
