const { assert, use } = require("chai");
const chaiAlmost = require("chai-almost");
const axios = require("axios");
const csv = require("csvtojson");

use(chaiAlmost());

const versions = require("../../../publish/polygon/versions.json");

// Coingecko API
const coingeckoNetwork = "polygon-pos";

const main = async (initializeData) => {
  const { assetsFileName, version, poolFactoryProxy } = initializeData;

  // Check Assets settings against latest Assets CSV file
  console.log("Checking assets..");

  const assets = versions[version].contracts.Assets;
  const csvAssets = await csv().fromFile(assetsFileName);

  // Check for any new assets in the CSV
  for (const csvAsset of csvAssets) {
    let foundInVersions = false;
    for (const asset of assets) {
      if (csvAsset.Address === asset.asset) foundInVersions = true;
    }
    assert(foundInVersions, `Couldn't find ${csvAsset["Asset Name"]} address in published versions.json list.`);
  }

  for (const asset of assets) {
    const assetAddress = asset.asset;
    const assetPrice = parseInt(await poolFactoryProxy.getAssetPrice(assetAddress));
    const assetType = parseInt(await poolFactoryProxy.getAssetType(assetAddress));

    assert(assetPrice > 0, `${asset.name} price is not above 0`);
    assert(
      assetType == parseInt(asset.assetType),
      `${asset.name} assetType mismatch. Deployed assetType = ${asset.assetType}, Contract assetType = ${assetType}`,
    );

    let foundInCsv = false;
    for (const csvAsset of csvAssets) {
      if (csvAsset.Address == assetAddress) {
        foundInCsv = true;
        assert(
          assetType == parseInt(csvAsset.AssetType),
          `${asset.name} assetType mismatch. CSV assetType = ${csvAsset.AssetType}, Contract assetType = ${assetType}`,
        );
      }
    }
    assert(foundInCsv, `Couldn't find ${asset.name} address in the Assets CSV.`);

    // Check primitive asset prices against Coingecko (correct price oracle config)
    const assetPriceUsd = assetPrice / 1e18;
    let coingeckoAssetPriceUsd;

    if (assetType == 0 || assetType == 1 || assetType == 4) {
      const url = `https://api.coingecko.com/api/v3/simple/token_price/${coingeckoNetwork}?contract_addresses=${assetAddress}&vs_currencies=usd&include_market_cap=false&include_24hr_vol=false&include_24hr_change=false&include_last_updated_at=true`;
      try {
        const { data } = await axios.get(url);
        coingeckoAssetPriceUsd = data[assetAddress].usd;

        const approxEq = (v1, v2, diff = 0.01) => Math.abs(1 - v1 / v2) <= diff;

        assert(
          approxEq(assetPriceUsd, coingeckoAssetPriceUsd),
          `${asset.name} price doesn't match Coingecko. dHEDGE price ${assetPriceUsd}, Coingecko price ${coingeckoAssetPriceUsd}`,
        );
      } catch (err) {
        console.error(err);
      }
    }
    console.log(
      `${asset.name} Asset type: ${assetType}, Asset price: ${assetPriceUsd}, Coingecko price: ${coingeckoAssetPriceUsd}`,
    );
  }

  console.log("Asset checks complete!");
  console.log("_________________________________________");
};

module.exports = { main };
