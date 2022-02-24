import csv from "csvtojson";
import Decimal from "decimal.js";
import fs from "fs";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { checkBalancerLpAsset, hasDuplicates, proposeTx, tryVerify } from "../../Helpers";
import { ICSVAsset, IJob, IProposeTxProperties, IUpgradeConfig, IVersions } from "../../types";

// Todo: Combine csvAssets and Balancer Assets into one JSON file (move away from csv)
export const assetsJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  // TODO: This optimally should not be mutated
  versions: IVersions,
  filenames: { assetsFileName?: string; balancerConfigFileName?: string },
  addresses: { balancerV2VaultAddress?: string } & IProposeTxProperties,
) => {
  const ethers = hre.ethers;
  let newOracles: ICSVAsset[] = [];

  // look up to check if csvAsset is in the current versions
  const fileName = filenames.assetsFileName;
  if (!fileName) {
    throw new Error("No assetFileName configured");
  }

  const csvAssets: ICSVAsset[] = await csv().fromFile(fileName);

  // Check for any accidental duplicate addresses or price feeds in the CSV
  if (await hasDuplicates(csvAssets, "assetAddress")) throw "Duplicate 'Address' field found in assets CSV";
  if (await hasDuplicates(csvAssets, "oracleAddress")) throw "Duplicate 'oracleAddress' field found in assets CSV";

  for (const csvAsset of [...csvAssets]) {
    // TODO: We don't redeploy any assets that are already configure in Versions.json if the configuration changes
    // For now, to redeploy an asset, delete it manually from versions.json.
    const foundInVersions = versions[config.newTag].contracts.Assets?.some((x) =>
      csvAssets.some((y) => x.assetAddress.toLowerCase() == y.assetAddress.toLowerCase()),
    );

    if (!foundInVersions) {
      console.log("Will Deploy Asset:", csvAsset);
      if (config.execute) {
        const oracle = await getOracle(hre, csvAsset, versions);
        newOracles.push(oracle);
      }
    }
  }

  // Should refactor not to use require and add types for what a balancerLp is
  const balancerLps = filenames.balancerConfigFileName
    ? JSON.parse(fs.readFileSync(filenames.balancerConfigFileName, "utf-8"))
    : [];
  const poolFactoryProxy = versions[config.oldTag].contracts.PoolFactoryProxy;
  const poolFactory = await ethers.getContractAt("PoolFactory", poolFactoryProxy);

  for (const balancerLp of balancerLps) {
    if (!addresses.balancerV2VaultAddress) {
      throw new Error("No balancerV2VaultAddress configured");
    }
    const foundInVersions = await checkBalancerLpAsset(
      balancerLp,
      versions[config.oldTag].contracts,
      poolFactory,
      newOracles,
    );
    if (!foundInVersions) {
      console.log("Will deploy Balancer V2 LP asset", balancerLp.name);
      if (config.execute) {
        // Deploy Balancer LP Aggregator
        console.log("Deploying ", balancerLp.name);
        const balancerV2Aggregator = await deployBalancerV2LpAggregator(
          addresses.balancerV2VaultAddress,
          versions[config.oldTag].contracts.PoolFactoryProxy,
          balancerLp.data,
          hre,
        );
        console.log(`${balancerLp.name} BalancerV2LPAggregator deployed at ${balancerV2Aggregator.address}`);
        newOracles.push({
          assetName: balancerLp.name,
          assetAddress: balancerLp.data.pool,
          assetType: balancerLp.assetType,
          oracleAddress: balancerV2Aggregator.address,
          oracleName: "BalancerV2LPAggregator",
        });
      }
    }
  }

  const AssetHandlerLogic = await hre.artifacts.readArtifact("AssetHandler");
  const assetHandlerLogic = new ethers.utils.Interface(AssetHandlerLogic.abi);
  const addAssetsABI = assetHandlerLogic.encodeFunctionData("addAssets", [newOracles]);

  if (newOracles.length > 0) {
    await proposeTx(
      versions[config.oldTag].contracts.AssetHandlerProxy,
      addAssetsABI,
      "Update assets in Asset Handler",
      config,
      addresses,
    );
    versions[config.newTag].contracts.Assets = [...(versions[config.newTag].contracts.Assets || []), ...newOracles];
  }
};

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
  switch (csvAsset.oracleName) {
    case "DHedgePoolAggregator":
      const { ethers } = hre;
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

      const USDPriceAggregator = await ethers.getContractFactory("USDPriceAggregator");
      const usdPriceAggregator = await USDPriceAggregator.deploy();
      await usdPriceAggregator.deployed();
      return usdPriceAggregator.address;

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
      return synthPriceAggregator.address;
    case "DeployedOracle":
      if (csvAsset.oracleAddress) {
        return csvAsset.oracleAddress;
      }
      const deployedOracle = versions[latestVersion].contracts.Oracles?.find(
        (oracle) => oracle.assetAddress == csvAsset.assetAddress,
      );
      if (!deployedOracle) {
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

const deployBalancerV2LpAggregator = async (
  balancerV2VaultAddress: string,
  factory: string,
  info: any,
  hre: HardhatRuntimeEnvironment,
) => {
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

  await hre.run("compile:one", { contractName: "BalancerV2LPAggregator" });

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
    "contracts/assets/BalancerV2LPAggregator.sol:BalancerV2LPAggregator",
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
  return balancerV2LpAggregator;
};
