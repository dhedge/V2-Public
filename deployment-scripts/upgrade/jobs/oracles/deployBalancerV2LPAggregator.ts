import Decimal from "decimal.js";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { tryVerify } from "../../../Helpers";
import { Address } from "../../../types";
import { TAssetConfig, TOracleDeployer, IBalancerV2LPAggregatorConfig } from "./oracleTypes";

export const deployBalancerV2LPAggregator: TOracleDeployer = async (
  hre: HardhatRuntimeEnvironment,
  oracleConfig: TAssetConfig,
): Promise<Address> => {
  const specificConfig = validateConfig(oracleConfig);

  return deployBalancerV2LpAggregator(
    specificConfig.balancerV2VaultAddress,
    specificConfig.dhedgeFactoryProxy,
    oracleConfig.assetAddress,
    hre,
  );
};

const validateConfig = (oracleConfig: TAssetConfig): IBalancerV2LPAggregatorConfig => {
  const specificOracleConfig = oracleConfig.specificOracleConfig;
  throw new Error("Needs to be implemented");
  return specificOracleConfig as IBalancerV2LPAggregatorConfig;
};

export const deployBalancerV2LpAggregator = async (
  balancerV2VaultAddress: string,
  factory: string,
  pool: string,
  hre: HardhatRuntimeEnvironment,
): Promise<Address> => {
  const weights: Decimal[] = (
    await (await hre.ethers.getContractAt("IBalancerWeightedPool", pool)).getNormalizedWeights()
  ).map((w) => new Decimal(w.toString()).div(hre.ethers.utils.parseEther("1").toString()));
  console.log("BalancerV2LPAggregator ", pool, " : ", weights.toString());

  const ether = "1000000000000000000";
  const divisor = weights.reduce((acc: any, w: any, i: any) => {
    if (i == 0) {
      return new Decimal(w).pow(w);
    }
    return acc.mul(new Decimal(w).pow(w));
  }, new Decimal("0"));

  const K = new Decimal(ether).div(divisor).toFixed(0);

  let matrix = [];
  for (let i = 1; i <= 20; i++) {
    const elements = [new Decimal(10).pow(i).times(ether).toFixed(0)];
    for (let j = 0; j < weights.length; j++) {
      elements.push(new Decimal(10).pow(i).pow(weights[j]).times(ether).toFixed(0));
    }
    matrix.push(elements);
  }

  const BalancerV2LPAggregator = await hre.ethers.getContractFactory("BalancerV2LPAggregator");

  const balancerV2LpAggregator = await BalancerV2LPAggregator.deploy(factory, balancerV2VaultAddress, pool, [
    "50000000000000000", // maxPriceDeviation: 0.05
    K,
    "100000000", // powerPrecision
    matrix, // approximationMatrix
  ] as any);
  await balancerV2LpAggregator.deployed();

  await tryVerify(
    hre,
    balancerV2LpAggregator.address,
    "contracts/priceAggregators/BalancerV2LPAggregator.sol:BalancerV2LPAggregator",
    [
      factory,
      balancerV2VaultAddress,
      pool,
      [
        "50000000000000000", // maxPriceDeviation: 0.05
        K,
        "100000000", // powerPrecision
        matrix, // approximationMatrix
      ],
    ],
  );
  return balancerV2LpAggregator.address;
};
