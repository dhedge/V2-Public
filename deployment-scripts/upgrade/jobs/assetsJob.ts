import Decimal from "decimal.js";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { checkAsset, checkBalancerLpAsset, getAggregator, hasDuplicates, proposeTx, tryVerify } from "../../Helpers";
import { IJob, IProposeTxProperties, IUpgradeConfig, IVersions } from "../../types";
import fs from "fs";
import csv from "csvtojson";

export const assetsJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  // TODO: This optimally should not be mutated
  versions: IVersions,
  filenames: { assetsFileName?: string; balancerConfigFileName?: string },
  addresses: { balancerV2VaultAddress?: string } & IProposeTxProperties,
) => {
  const ethers = hre.ethers;
  let assetHandlerAssets = [];
  const poolFactoryProxy = versions[config.oldTag].contracts.PoolFactoryProxy;
  const poolFactory = await ethers.getContractAt("PoolFactory", poolFactoryProxy);

  // look up to check if csvAsset is in the current versions
  const fileName = filenames.assetsFileName;
  if (!fileName) {
    throw new Error("No assetFileName configured");
  }

  const csvAssets = await csv().fromFile(fileName);

  // Check for any accidental duplicate addresses or price feeds in the CSV
  if (await hasDuplicates(csvAssets, "Address")) throw "Duplicate 'Address' field found in assets CSV";
  if (await hasDuplicates(csvAssets, "ChainlinkPriceFeed"))
    throw "Duplicate 'ChainlinkPriceFeed' field found in assets CSV";

  const SushiLPAggregator = await ethers.getContractFactory("UniV2LPAggregator");
  for (const csvAsset of csvAssets) {
    const foundInVersions = await checkAsset(
      csvAsset,
      versions[config.oldTag].contracts,
      poolFactory,
      assetHandlerAssets,
    );

    if (!foundInVersions) {
      const assetType = csvAsset.AssetType;
      let usdPriceAggregatorAddress;

      switch (assetType) {
        case "2":
          console.log("Will deploy asset", csvAsset["AssetName"]);
          if (!config.execute) {
            break;
          }

          // Deploy Sushi LP Aggregator
          console.log("Deploying ", csvAsset["AssetName"]);
          const sushiLPAggregator = await SushiLPAggregator.deploy(
            csvAsset.Address,
            versions[config.oldTag].contracts.PoolFactoryProxy,
          );
          await sushiLPAggregator.deployed();
          console.log(`${csvAsset["AssetName"]} SushiLPAggregator deployed at ${sushiLPAggregator.address}`);
          assetHandlerAssets.push({
            name: csvAsset["AssetName"],
            asset: csvAsset.Address,
            assetType: assetType,
            aggregator: sushiLPAggregator.address,
            AggregatorName: csvAsset.AggregatorName,
          });
          break;
        case "3":
          console.log("Will deploy asset", csvAsset["AssetName"]);
          if (!config.execute) {
            break;
          }

          if (!csvAsset["ChainlinkPriceFeed"]) {
            usdPriceAggregatorAddress = await deployUsdPriceAggregator(hre);
          } else {
            // Use configured USDPriceAggregator
            usdPriceAggregatorAddress = csvAsset["ChainlinkPriceFeed"];
          }

          console.log("USDPriceAggregator deployed at", usdPriceAggregatorAddress);
          assetHandlerAssets.push({
            name: csvAsset["AssetName"],
            asset: csvAsset.Address,
            assetType: assetType,
            aggregator: usdPriceAggregatorAddress,
            AggregatorName: csvAsset.AggregatorName,
          });
          break;
        case "7":
          console.log("Will deploy asset", csvAsset["AssetName"]);
          if (!config.execute) {
            break;
          }

          if (!csvAsset["ChainlinkPriceFeed"]) {
            usdPriceAggregatorAddress = await deployUsdPriceAggregator(hre);
          } else {
            // Use configured USDPriceAggregator
            usdPriceAggregatorAddress = csvAsset["ChainlinkPriceFeed"];
          }

          console.log("USDPriceAggregator deployed at", usdPriceAggregatorAddress);
          assetHandlerAssets.push({
            name: csvAsset["AssetName"],
            asset: csvAsset.Address,
            assetType: assetType,
            aggregator: usdPriceAggregatorAddress,
            AggregatorName: csvAsset.AggregatorName,
          });
          break;
        default:
          console.log("Will deploy asset", csvAsset["AssetName"]);
          if (!config.execute) {
            break;
          }
          console.log(`Adding new asset to AssetHandler: ${csvAsset["AssetName"]}`);
          const aggregator = await getAggregator(hre, csvAsset);
          assetHandlerAssets.push({
            name: csvAsset["AssetName"],
            asset: csvAsset.Address,
            assetType: assetType,
            aggregator: aggregator,
            AggregatorName: csvAsset.AggregatorName,
          });
      }
    }
  }

  // Should refactor not to use require and add types for what a balancerLp is
  const balancerLps = filenames.balancerConfigFileName
    ? JSON.parse(fs.readFileSync(filenames.balancerConfigFileName, "utf-8"))
    : [];

  for (const balancerLp of balancerLps) {
    if (!addresses.balancerV2VaultAddress) {
      throw new Error("No balancerV2VaultAddress configured");
    }
    const foundInVersions = await checkBalancerLpAsset(
      balancerLp,
      versions[config.oldTag].contracts,
      poolFactory,
      assetHandlerAssets,
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
        assetHandlerAssets.push({
          name: balancerLp.name,
          asset: balancerLp.data.pool,
          assetType: balancerLp.assetType,
          aggregator: balancerV2Aggregator.address,
          AggregatorName: "BalancerV2LPAggregator",
        });
      }
    }
  }

  const AssetHandlerLogic = await hre.artifacts.readArtifact("AssetHandler");
  const assetHandlerLogic = new ethers.utils.Interface(AssetHandlerLogic.abi);
  const addAssetsABI = assetHandlerLogic.encodeFunctionData("addAssets", [assetHandlerAssets]);

  if (assetHandlerAssets.length > 0) {
    await proposeTx(
      versions[config.oldTag].contracts.AssetHandlerProxy,
      addAssetsABI,
      "Update assets in Asset Handler",
      config,
      addresses,
    );
    versions[config.newTag].contracts.Assets = [
      ...(versions[config.newTag].contracts.Assets || []),
      ...assetHandlerAssets,
    ];
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

const deployUsdPriceAggregator = async (hre: HardhatRuntimeEnvironment) => {
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
