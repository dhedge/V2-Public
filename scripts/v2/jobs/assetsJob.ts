import Decimal from "decimal.js";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { checkAsset, checkBalancerLpAsset, getAggregator, hasDuplicates, proposeTx, tryVerify } from "../../Helpers";
import { IJob, IUpgradeConfig } from "../types";
const csv = require("csvtojson");

export const assetsJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  // TODO: This should be types and optimally should not be mutated
  versions: any,
  filenames: { assetsFileName?: string; balancerConfigFileName?: string },
  addresses: { balancerV2VaultAddress?: string },
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
  if (await hasDuplicates(csvAssets, "Chainlink Price Feed"))
    throw "Duplicate 'Chainlink Price Feed' field found in assets CSV";

  console.log("existing assets", csvAssets);

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
      switch (assetType) {
        case "2":
          console.log("Will deploy asset", csvAsset["Asset Name"]);
          if (!config.execute) {
            break;
          }

          // Deploy Sushi LP Aggregator
          console.log("Deploying ", csvAsset["Asset Name"]);
          const sushiLPAggregator = await SushiLPAggregator.deploy(
            csvAsset.Address,
            versions[config.oldTag].contracts.PoolFactoryProxy,
          );
          await sushiLPAggregator.deployed();
          console.log(`${csvAsset["Asset Name"]} SushiLPAggregator deployed at ${sushiLPAggregator.address}`);
          assetHandlerAssets.push({
            name: csvAsset["Asset Name"],
            asset: csvAsset.Address,
            assetType: assetType,
            aggregator: sushiLPAggregator.address,
            aggregatorName: csvAsset.aggregatorName,
          });
          break;
        case "3":
          console.log("Will deploy asset", csvAsset["Asset Name"]);
          if (!config.execute) {
            break;
          }

          let usdPriceAggregatorAddress;
          if (!csvAsset["Chainlink Price Feed"]) {
            // Deploy USDPriceAggregator
            const USDPriceAggregator = await ethers.getContractFactory("USDPriceAggregator");
            const usdPriceAggregator = await USDPriceAggregator.deploy();
            await usdPriceAggregator.deployed();
            usdPriceAggregatorAddress = usdPriceAggregator.address;
          } else {
            // Use configured USDPriceAggregator
            usdPriceAggregatorAddress = csvAsset["Chainlink Price Feed"];
          }

          console.log("USDPriceAggregator deployed at", usdPriceAggregatorAddress);
          assetHandlerAssets.push({
            name: csvAsset["Asset Name"],
            asset: csvAsset.Address,
            assetType: assetType,
            aggregator: usdPriceAggregatorAddress,
            aggregatorName: csvAsset.aggregatorName,
          });
          break;
        default:
          console.log("Will deploy asset", csvAsset["Asset Name"]);
          if (!config.execute) {
            break;
          }
          console.log(`Adding new asset to AssetHandler: ${csvAsset["Asset Name"]}`);
          const aggregator = await getAggregator(hre, csvAsset);
          assetHandlerAssets.push({
            name: csvAsset["Asset Name"],
            asset: csvAsset.Address,
            assetType: assetType,
            aggregator: aggregator,
            aggregatorName: csvAsset.aggregatorName,
          });
      }
    } else {
      console.log("Found in versions", csvAsset);
    }
  }

  // Should refactor not to use require and add types for what a balancerLp is
  const balancerLps = filenames.balancerConfigFileName ? require(process.cwd() + filenames.balancerConfigFileName) : [];
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
          aggregatorName: "BalancerV2LPAggregator",
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
      config.execute,
      config.restartnonce,
    );
    versions[config.newTag].contracts.Assets = [...versions[config.newTag].contracts.Assets, ...assetHandlerAssets];
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
