const { assert, use } = require("chai");
const chaiAlmost = require("chai-almost");
const axios = require("axios");
const csv = require("csvtojson");

use(chaiAlmost());

// Coingecko API
const coingeckoNetwork = "polygon-pos";

const approxEq = (v1, v2, diff = 0.01) => Math.abs(1 - v1 / v2) <= diff;

const main = async (initializeData) => {
  const { versions, version, assetsFileName, balancerLps, poolFactoryProxy, balancerV2Vault, assetHandlerProxy } =
    initializeData;

  // Check Assets settings against latest Assets CSV file
  console.log("Checking assets..");

  const assets = versions[version].contracts.Assets;
  const csvAssets = await csv().fromFile(assetsFileName);

  // Check for any new assets in the asset CSV config
  for (const csvAsset of csvAssets) {
    let foundInVersions = false;
    for (const asset of assets) {
      if (csvAsset.Address === asset.asset) foundInVersions = true;
    }
    assert(foundInVersions, `Couldn't find ${csvAsset["Asset Name"]} address in published versions.json list.`);
  }

  // Check for any new assets in the Balancer JSON config
  for (const balancerLp of balancerLps) {
    let foundInVersions = false;
    for (const asset of assets) {
      if (balancerLp.address === asset.asset) {
        foundInVersions = true;
        console.log("Checking", balancerLp.name);
        await checkBalancerLpAsset(balancerLp, balancerV2Vault, poolFactoryProxy, assetHandlerProxy);
      }
    }
    assert(foundInVersions, `Couldn't find ${balancerLp.name} address in published versions.json list.`);
  }

  for (const asset of assets) {
    const assetAddress = asset.asset;
    const assetPrice = parseInt(await poolFactoryProxy.getAssetPrice(assetAddress));
    const assetType = parseInt(await poolFactoryProxy.getAssetType(assetAddress));

    assert(assetPrice > 0, `${asset.name} price is not above 0`);
    assert(
      assetType == parseInt(asset.assetType),
      `${asset.name} assetType mismatch. Deployed version ${version} assetType = ${asset.assetType}, Contract assetType = ${assetType}`,
    );

    let foundInCsv = false;

    // Reverse check Asset CSV config
    for (const csvAsset of csvAssets) {
      if (csvAsset.Address == assetAddress) {
        foundInCsv = true;
        assert(
          assetType == parseInt(csvAsset.AssetType),
          `${asset.name} assetType mismatch. CSV assetType = ${csvAsset.AssetType}, Contract assetType = ${assetType}`,
        );
      }
    }

    // Reverse check Balancer LP JSON config
    for (const balancerLp of balancerLps) {
      if (balancerLp.address === asset.asset) {
        foundInCsv = true;
        assert(
          assetType == parseInt(balancerLp.assetType),
          `${asset.name} assetType mismatch. Balancer LP JSON assetType = ${balancerLp.AssetType}, Contract assetType = ${assetType}`,
        );
      }
    }

    assert(foundInCsv, `Couldn't find ${asset.name} address in the Assets CSV or Balancer JSON config.`);

    // Check primitive asset prices against Coingecko (correct price oracle config)
    const assetPriceUsd = assetPrice / 1e18;
    let coingeckoAssetPriceUsd;

    // Skip Coingecko price checks for some assets that don't exist on Coingecko
    const checkCoingeckoPrice =
      !asset.name.includes("Balancer LP") &&
      !asset.name.includes("dUSD") &&
      (assetType == 0 || assetType == 1 || assetType == 4)
        ? true
        : false;

    if (checkCoingeckoPrice) {
      const url = `https://api.coingecko.com/api/v3/simple/token_price/${coingeckoNetwork}?contract_addresses=${assetAddress}&vs_currencies=usd&include_market_cap=false&include_24hr_vol=false&include_24hr_change=false&include_last_updated_at=true`;
      try {
        const { data } = await axios.get(url);
        coingeckoAssetPriceUsd = data[assetAddress.toLowerCase()].usd;

        assert(
          approxEq(assetPriceUsd, coingeckoAssetPriceUsd),
          `${asset.name} price doesn't match Coingecko. dHEDGE price ${assetPriceUsd}, Coingecko price ${coingeckoAssetPriceUsd}`,
        );
      } catch (err) {
        console.error(err);
        console.error(`Error getting Coingecko feed for ${asset.name}`);
      }
    }

    console.log(
      `${asset.name} Asset type: ${assetType}, Asset price: ${assetPriceUsd}, Coingecko price: ${coingeckoAssetPriceUsd}`,
    );
  }

  console.log("Asset checks complete!");
  console.log("_________________________________________");
};

const checkBalancerLpAsset = async (balancerLp, balancerV2Vault, poolFactoryProxy, assetHandlerProxy) => {
  const balancerLPAggregator = await assetHandlerProxy.priceAggregators(balancerLp.address);
  const BalancerV2LPAggregator = await hre.artifacts.readArtifact("BalancerV2LPAggregator");
  const aggregator = await ethers.getContractAt(BalancerV2LPAggregator.abi, balancerLPAggregator);
  const poolTokens = (await balancerV2Vault.getPoolTokens(balancerLp.data.poolId))[0];
  const assetType = parseInt(await poolFactoryProxy.getAssetType(balancerLp.address));

  // check Balancer LP asset type configuration
  assert(assetType === balancerLp.assetType, `${balancerLp.name} deployed asset type mismatch with configuration.`);

  // check Balancer LP token configuration
  assert(
    poolTokens.length === balancerLp.data.tokens.length,
    `${balancerLp.name} pool tokens length mismatch with configuration.`,
  );

  // get token weights
  const pool = await ethers.getContractAt(
    [
      {
        inputs: [],
        name: "getNormalizedWeights",
        outputs: [{ internalType: "uint256[]", name: "", type: "uint256[]" }],
        stateMutability: "view",
        type: "function",
      },
    ],
    balancerLp.address,
  );
  let weights;
  try {
    weights = await pool.getNormalizedWeights();
  } catch (error) {
    weights = ["500000000000000000", "500000000000000000"]; // no normalized weights on a 50/50 pool
  }

  for (let i = 0; i < poolTokens.length; i++) {
    assert(
      poolTokens[i].toLowerCase() === balancerLp.data.tokens[i].toLowerCase(),
      `${balancerLp.name} pool token address mismatch with configuration.`,
    );
    const aggregatorPoolToken = await aggregator.tokens(i);
    assert(
      aggregatorPoolToken.toLowerCase() === balancerLp.data.tokens[i].toLowerCase(),
      `${balancerLp.name} pool token address mismatch with deployment.`,
    );

    // check token decimals
    const IERC20 = await hre.artifacts.readArtifact("IERC20Extended");
    const token = await ethers.getContractAt(IERC20.abi, poolTokens[i]);
    const decimals = await token.decimals();
    assert(
      decimals === balancerLp.data.decimals[i],
      `${balancerLp.name} pool token ${poolTokens[i]} decimals mismatch with configuration.`,
    );
    const aggregatorPoolDecimals = await aggregator.decimals(i);
    assert(
      aggregatorPoolDecimals === balancerLp.data.decimals[i],
      `${balancerLp.name} pool token decimals mismatch with deployment.`,
    );

    assert(
      weights[i] / 1e18 === balancerLp.data.weights[i],
      `${balancerLp.name} pool token ${poolTokens[i]} weights mismatch with configuration.`,
    );
    const aggregatorPoolWeights = await aggregator.weights(i);
    assert(
      aggregatorPoolWeights / 1e18 === balancerLp.data.weights[i],
      `${balancerLp.name} pool token weights mismatch with deployment.`,
    );
  }
};

module.exports = { main };
