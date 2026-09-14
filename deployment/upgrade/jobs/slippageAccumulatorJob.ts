import { HardhatRuntimeEnvironment } from "hardhat/types";
import { tryVerify } from "../../deploymentHelpers";
import { IJob, IAddresses, IUpgradeConfig, IVersions, IFileNames } from "../../types";

export const slippageAccumulatorJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  _: IFileNames,
  addresses: IAddresses,
) => {
  const ethers = hre.ethers;

  if (config.execute) {
    console.log("Will deploy slippage accumulator");

    if (!versions[config.oldTag].contracts.PoolFactoryProxy) return console.log("No pool factory proxy address");

    const SlippageAccumulatorFactory = await ethers.getContractFactory("SlippageAccumulator");
    const args: [string, number, number] = [
      versions[config.oldTag].contracts.PoolFactoryProxy,
      addresses.slippageAccumulator.decayTime,
      addresses.slippageAccumulator.maxCumulativeSlippage,
    ];
    const slippageAccumulator = await SlippageAccumulatorFactory.deploy(...args);
    await slippageAccumulator.deployed();
    console.log("Slippage accumulator deployed at ", slippageAccumulator.address);

    await tryVerify(
      hre,
      slippageAccumulator.address,
      "contracts/utils/SlippageAccumulator.sol:SlippageAccumulator",
      args,
    );

    await slippageAccumulator.transferOwnership(addresses.protocolDaoAddress);

    versions[config.newTag].contracts.SlippageAccumulator = slippageAccumulator.address;

    // NOTE: Contract guards bind the accumulator address immutably in their constructor, so every guard
    // inheriting SlippageAccumulatorUser that is live on this chain must be redeployed in the same run.
    console.log(
      "Re-deploy every contract guard inheriting SlippageAccumulatorUser that is live on this chain:\n" +
        " - find inheritors: grep -rl SlippageAccumulatorUser contracts/guards/contractGuards\n" +
        " - live on this chain: cross-check guard names against config/{chain}/dHEDGE Governance Contract Guards.csv\n" +
        " - watch for chain-specific subclasses without their own upgrade job (e.g. PendleRouterV4PlasmaContractGuard)\n",
    );
  }
};
