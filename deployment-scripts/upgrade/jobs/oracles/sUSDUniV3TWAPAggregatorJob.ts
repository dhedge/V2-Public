import { HardhatRuntimeEnvironment } from "hardhat/types";
import { tryVerify } from "../../../Helpers";
import {
  IJob,
  IProposeTxProperties,
  IUpgradeConfig,
  IVersions,
  sUSDUniV3TWAPAggregatorProperties,
} from "../../../types";

export const sUSDUniV3TWAPAggregatorJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  // TODO: This optimally should not be mutated
  versions: IVersions,
  // eslint-disable-next-line @typescript-eslint/ban-types
  _: {},
  addresses: IProposeTxProperties & sUSDUniV3TWAPAggregatorProperties,
) => {
  const ethers = hre.ethers;
  if (!addresses.sUSDAddress || !addresses.sUSDDaiUniV3PoolAddress || !addresses.daiChainlinkOracleAddress) {
    throw new Error("Missing Configuration for sUSDUniV3TWAPAggregatorJob");
  }

  console.log("Will deploy sUSDUniV3TWAPAggregator");
  if (config.execute) {
    const UniV3TWAPAggregator = await ethers.getContractFactory("UniV3TWAPAggregator");
    console.log("Deploying sUSDUniV3TWAPAggregator..");
    const uniV3TWAPAggregator = await UniV3TWAPAggregator.deploy(
      addresses.sUSDDaiUniV3PoolAddress,
      addresses.sUSDAddress,
      addresses.daiChainlinkOracleAddress,
      98000000, // $0.98 lower limit
      102000000, // $1.02 upper limit
      60 * 10, // 10 mins update interval
    );
    await uniV3TWAPAggregator.deployed();

    // wait 5 confirmations before verifying
    const tx = uniV3TWAPAggregator.deployTransaction;
    await tx.wait(5);
    await tryVerify(
      hre,
      uniV3TWAPAggregator.address,
      "contracts/priceAggregators/UniV3TWAPAggregator.sol:UniV3TWAPAggregator",
      [
        addresses.sUSDDaiUniV3PoolAddress,
        addresses.sUSDAddress,
        addresses.daiChainlinkOracleAddress,
        98000000, // $0.98 lower limit
        102000000, // $1.02 upper limit
        60 * 10, // 10 mins update interval
      ],
    );

    versions[config.newTag].contracts.Oracles = [
      ...(versions[config.newTag].contracts.Oracles || []),
      {
        assetAddress: addresses.sUSDAddress,
        oracleAddress: uniV3TWAPAggregator.address,
        oracleName: "susdUniV3TWAPAggregator",
      },
    ];
  }
};
