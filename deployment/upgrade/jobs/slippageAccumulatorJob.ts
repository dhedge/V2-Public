import { HardhatRuntimeEnvironment } from "hardhat/types";
import { tryVerify } from "../../deploymentHelpers";
import { IJob, IProposeTxProperties, IUpgradeConfig, IVersions, IFileNames } from "../../types";

export const slippageAccumulatorJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  // TODO: This optimally should not be mutated
  versions: IVersions,
  _: IFileNames,
  addresses: IProposeTxProperties,
) => {
  const ethers = hre.ethers;

  if (config.execute) {
    console.log("Will deploy slippage accumulator");

    console.log("PoolFactory proxy address:", versions[config.oldTag].contracts.PoolFactoryProxy);

    const SlippageAccumulatorFactory = await ethers.getContractFactory("SlippageAccumulator");
    const args: [string, number, number] = [versions[config.oldTag].contracts.PoolFactoryProxy, 86400, 10e4]; // [poolFactory address, decayTime, maxCumulativeSlippage]
    const slippageAccumulator = await SlippageAccumulatorFactory.deploy(...args);
    await slippageAccumulator.deployed();
    console.log("Slippage accumulator deployed at ", slippageAccumulator.address);

    await tryVerify(
      hre,
      slippageAccumulator.address,
      "contracts/utils/SlippageAccumulator.sol:SlippageAccumulator",
      args,
    );

    console.log("Transfering ownership");

    await slippageAccumulator.transferOwnership(addresses.protocolDaoAddress);

    versions[config.newTag].contracts.SlippageAccumulator = slippageAccumulator.address;

    // NOTE: Whenever a new slippage accumulator is deployed, the following contract guards need to be redeployed:
    // - BalancerV2Guard.sol
    // - OneInchV5Guard.sol
    // - UniswapV2RouterGuard.sol
    // - UniswapV3RouterGuard.sol
    console.log(
      "Please re-deploy the following contract guards: \n - BalancerV2Guard\n - OneInchV5Guard\n - UniswapV2RouterGuard\n - UniswapV3RouterGuard\n",
    );
  }
};
