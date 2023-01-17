import Decimal from "decimal.js";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { tryVerify } from "../../../Helpers";
import { Address } from "../../../types";
import { TAssetConfig, TOracleDeployer, IBalancerV2LPAggregatorSpecificConfig, IAssetConfig } from "./oracleTypes";

export const deployBalancerV2LPAggregator: TOracleDeployer = async (
  hre: HardhatRuntimeEnvironment,
  oracleConfig: TAssetConfig,
): Promise<Address> => {
  const specificConfig = validateConfig(oracleConfig);

  return deployBalancerV2LpAggregator(specificConfig.dhedgeFactoryProxy, oracleConfig.assetAddress, hre);
};

const isBalancerV2LPAggregator = (
  oracleConfig: TAssetConfig,
): oracleConfig is IAssetConfig<"BalancerV2LPAggregator", IBalancerV2LPAggregatorSpecificConfig> => {
  const requiredFields = ["dhedgeFactoryProxy"];
  const { specificOracleConfig } = oracleConfig;
  if (
    oracleConfig.oracleType != "BalancerV2LPAggregator" ||
    !specificOracleConfig ||
    requiredFields.some((field) => !(field in oracleConfig.specificOracleConfig))
  ) {
    return false;
  }
  return true;
};

const validateConfig = (oracleConfig: TAssetConfig): IBalancerV2LPAggregatorSpecificConfig => {
  const specificOracleConfig = oracleConfig.specificOracleConfig;
  if (!isBalancerV2LPAggregator(oracleConfig)) {
    throw new Error("BalancerV2LPAggregator config incorrect: " + oracleConfig.assetAddress);
  }

  return specificOracleConfig as IBalancerV2LPAggregatorSpecificConfig;
};

export const deployBalancerV2LpAggregator = async (
  factory: string,
  pool: string,
  hre: HardhatRuntimeEnvironment,
): Promise<Address> => {
  const weights: Decimal[] = (
    await (await hre.ethers.getContractAt("IBalancerWeightedPool", pool)).getNormalizedWeights()
  )
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    .map((w: any) => new Decimal(w.toString()).div(hre.ethers.utils.parseEther("1").toString()));
  console.log("BalancerV2LPAggregator ", pool, " : ", weights.toString());

  const ether = "1000000000000000000";
  const divisor = weights.reduce((acc, w, i) => {
    if (i == 0) {
      return new Decimal(w).pow(w);
    }
    return acc.mul(new Decimal(w).pow(w));
  }, new Decimal("0"));

  const K = new Decimal(ether).div(divisor).toFixed(0);

  const matrix: string[][] = [];
  for (let i = 1; i <= 20; i++) {
    const elements = [new Decimal(10).pow(i).times(ether).toFixed(0)];
    for (let j = 0; j < weights.length; j++) {
      elements.push(new Decimal(10).pow(i).pow(weights[j]).times(ether).toFixed(0));
    }
    matrix.push(elements);
  }

  const BalancerV2LPAggregator = await hre.ethers.getContractFactory("BalancerV2LPAggregator");

  const params: {
    maxPriceDeviation: string;
    K: string;
    powerPrecision: string;
    approximationMatrix: string[][];
  } = {
    maxPriceDeviation: "50000000000000000", // maxPriceDeviation: 0.05
    K,
    powerPrecision: "100000000", // powerPrecision
    approximationMatrix: matrix, // approximationMatrix
  };
  const balancerV2LpAggregator = await BalancerV2LPAggregator.deploy(factory, pool, params);
  await balancerV2LpAggregator.deployed();

  await tryVerify(
    hre,
    balancerV2LpAggregator.address,
    "contracts/priceAggregators/BalancerV2LPAggregator.sol:BalancerV2LPAggregator",
    [
      factory,
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
