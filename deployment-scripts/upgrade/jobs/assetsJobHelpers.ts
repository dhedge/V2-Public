import Decimal from "decimal.js";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { tryVerify } from "../../Helpers";
import { Address, ICSVAsset, IVersions } from "../../types";

export interface IBalancerData {
  pool: string;
  poolId: string;
  tokens: string[];
  decimals: number[];
  weights: number[];
}

export interface IBalancerAsset {
  name: string;
  oracleName: "BalancerV2LPAggregator" | "BalancerLpStablePoolAggregator";
  address: string;
  assetType: number;
  data: IBalancerData;
}

export const getOracle = async (
  hre: HardhatRuntimeEnvironment,
  csvAsset: ICSVAsset,
  versions: IVersions,
): Promise<ICSVAsset> => {
  const oracleAddress = await getOracleAddress(hre, csvAsset, versions);
  return {
    ...csvAsset,
    oracleAddress,
  };
};

const getOracleAddress = async (
  hre: HardhatRuntimeEnvironment,
  csvAsset: ICSVAsset,
  versions: IVersions,
): Promise<string> => {
  const latestVersion = Object.keys(versions)[Object.keys(versions).length - 1];
  const { ethers } = hre;
  switch (csvAsset.oracleName) {
    case "DHedgePoolAggregator":
      const DHedgePoolAggregator = await ethers.getContractFactory("DHedgePoolAggregator");
      const dHedgePoolAggregator = await DHedgePoolAggregator.deploy(csvAsset.assetAddress);
      await dHedgePoolAggregator.deployed();
      await tryVerify(
        hre,
        dHedgePoolAggregator.address,
        "contracts/priceAggregators/DHedgePoolAggregator.sol:DHedgePoolAggregator",
        [csvAsset.assetAddress],
      );
      return dHedgePoolAggregator.address;
    case "USDPriceAggregator":
      // Deploy USDPriceAggregator
      if (csvAsset.oracleAddress) {
        return csvAsset.oracleAddress;
      }

      return deployUsdPriceAggregator(hre);

    case "UniV2LPAggregator":
      const SushiLPAggregator = await ethers.getContractFactory("UniV2LPAggregator");
      const sushiLPAggregator = await SushiLPAggregator.deploy(
        csvAsset.assetAddress,
        versions[latestVersion].contracts.PoolFactoryProxy,
      );

      await sushiLPAggregator.deployed();
      return sushiLPAggregator.address;
    case "SynthPriceAggregator":
      const susdPriceAggregator = versions[latestVersion].contracts.Oracles?.find(
        (x) => x.oracleName == "susdUniV3TWAPAggregator",
      );
      if (!susdPriceAggregator) {
        throw new Error("assetsJob.getOracleAddress.SynthPriceAggregator");
      }
      const SynthPriceAggregator = await ethers.getContractFactory("SynthPriceAggregator");
      const synthPriceAggregator = await SynthPriceAggregator.deploy(
        susdPriceAggregator.oracleAddress,
        csvAsset.oracleAddress,
      );
      synthPriceAggregator.deployed();
      await tryVerify(
        hre,
        synthPriceAggregator.address,
        "contracts/priceAggregators/SynthPriceAggregator.sol:SynthPriceAggregator",
        [susdPriceAggregator.oracleAddress, csvAsset.oracleAddress],
      );
      return synthPriceAggregator.address;
    case "DeployedOracle":
      if (csvAsset.oracleAddress) {
        return csvAsset.oracleAddress;
      }
      const deployedOracle = versions[latestVersion].contracts.Oracles?.find(
        (oracle) => oracle.assetAddress.toLowerCase() == csvAsset.assetAddress.toLowerCase(),
      );
      if (!deployedOracle) {
        console.log(versions[latestVersion].contracts.Oracles);
        throw new Error("assetsJob.getOracleAddress.DeployedOracle: No oracle found in versions.json");
      }

      return deployedOracle.oracleAddress;
    default:
      if (!csvAsset.oracleAddress) {
        throw new Error("assetsJob.getOracleAddress.default: No oracle address for: " + csvAsset.assetAddress);
      }
      return csvAsset.oracleAddress;
  }
};

export const deployBalancerV2LpAggregator = async (
  balancerV2VaultAddress: string,
  factory: string,
  info: IBalancerData,
  hre: HardhatRuntimeEnvironment,
): Promise<Address> => {
  const ether = "1000000000000000000";
  const divisor = info.weights.reduce((acc: any, w: any, i: any) => {
    if (i == 0) {
      return new Decimal(w).pow(w);
    }
    return acc.mul(new Decimal(w).pow(w));
  }, new Decimal("0"));

  const K = new Decimal(ether).div(divisor).toFixed(0);

  let matrix = [];
  for (let i = 1; i <= 20; i++) {
    const elements = [new Decimal(10).pow(i).times(ether).toFixed(0)];
    for (let j = 0; j < info.weights.length; j++) {
      elements.push(new Decimal(10).pow(i).pow(info.weights[j]).times(ether).toFixed(0));
    }
    matrix.push(elements);
  }

  const BalancerV2LPAggregator = await hre.ethers.getContractFactory("BalancerV2LPAggregator");

  const balancerV2LpAggregator = await BalancerV2LPAggregator.deploy(
    factory,
    balancerV2VaultAddress,
    info.pool,
    info.tokens,
    info.decimals,
    info.weights.map((w: any) => new Decimal(w).mul(ether).toFixed(0)),
    [
      "50000000000000000", // maxPriceDeviation: 0.05
      K,
      "100000000", // powerPrecision
      matrix, // approximationMatrix
    ] as any,
  );
  await balancerV2LpAggregator.deployed();

  await tryVerify(
    hre,
    balancerV2LpAggregator.address,
    "contracts/priceAggregators/BalancerV2LPAggregator.sol:BalancerV2LPAggregator",
    [
      factory,
      balancerV2VaultAddress,
      info.pool,
      info.tokens,
      info.decimals,
      info.weights.map((w: any) => new Decimal(w).mul(ether).toFixed(0)),
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

export const deployBalancerLpStablePoolAggregator = async (
  hre: HardhatRuntimeEnvironment,
  factory: string,
  pool: string,
): Promise<Address> => {
  const BalancerStablePoolAggregator = await hre.ethers.getContractFactory("BalancerStablePoolAggregator");

  const balancerStablePoolAggregator = await BalancerStablePoolAggregator.deploy(factory, pool);
  await balancerStablePoolAggregator.deployed();
  await tryVerify(
    hre,
    balancerStablePoolAggregator.address,
    "contracts/priceAggregators/BalancerStablePoolAggregator.sol:BalancerStablePoolAggregator",
    [factory, pool],
  );
  return balancerStablePoolAggregator.address;
};

export const deployUsdPriceAggregator = async (hre: HardhatRuntimeEnvironment) => {
  // Deploy USDPriceAggregator
  const USDPriceAggregator = await hre.ethers.getContractFactory("USDPriceAggregator");
  const usdPriceAggregator = await USDPriceAggregator.deploy();
  await usdPriceAggregator.deployed();
  const usdPriceAggregatorAddress = usdPriceAggregator.address;

  await tryVerify(
    hre,
    usdPriceAggregatorAddress,
    "contracts/priceAggregators/USDPriceAggregator.sol:USDPriceAggregator",
    [],
  );

  return usdPriceAggregatorAddress;
};
