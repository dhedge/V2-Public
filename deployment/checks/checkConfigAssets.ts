import axios from "axios";
import { assert } from "chai";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import fs from "fs";

import { InitType } from "./initialize";
import { TDeployedAsset } from "../types";

const approxEq = (v1: number, v2: number, diff = 0.01) => Math.abs(1 - v1 / v2) <= diff;

export const checkAssets = async (initializeData: InitType, hre: HardhatRuntimeEnvironment) => {
  const { network } = hre;
  // Coingecko API
  // https://www.coingecko.com/en/api/documentation - asset_platforms
  // asset_platforms
  const coingeckoNetwork = network.name == "polygon" ? "polygon-pos" : "optimistic-ethereum";

  const { versions, version, assetsFileName, poolFactoryProxy } = initializeData;

  // Check Assets settings against latest Assets CSV file
  console.log("Checking assets..");

  const assets = versions[version].contracts.Assets;
  const assetsConfig: TDeployedAsset[] = JSON.parse(fs.readFileSync(assetsFileName, "utf-8"));

  // Check for any new assets in the asset CSV config
  for (const assetConfig of assetsConfig) {
    let foundInVersions = false;
    for (const asset of assets) {
      if (assetConfig.assetAddress.toLowerCase() === asset.assetAddress.toLowerCase()) {
        foundInVersions = true;
      }
    }
    assert(foundInVersions, `Couldn't find ${assetConfig.assetName} address in published versions.json list.`);
  }

  for (const asset of assets) {
    const assetAddress = asset.assetAddress;
    const assetPrice = parseInt((await poolFactoryProxy.getAssetPrice(assetAddress)).toString());
    const assetType = parseInt((await poolFactoryProxy.getAssetType(assetAddress)).toString());

    assert(assetPrice > 0, `${asset.assetName} price is not above 0`);
    assert(
      assetType == asset.assetType,
      `${asset.assetName} assetType mismatch. Deployed version ${version} assetType = ${asset.assetType}, Contract assetType = ${assetType}`,
    );

    let foundInCsv = false;

    // Reverse check Asset CSV config
    for (const assetConfig of assetsConfig) {
      if (assetConfig.assetAddress == assetAddress) {
        foundInCsv = true;
        assert(
          assetType == assetConfig.assetType,
          `${asset.assetName} assetType mismatch. CSV assetType = ${assetConfig.assetType}, Contract assetType = ${assetType}`,
        );
      }
    }

    assert(foundInCsv, `Couldn't find ${asset.assetName} address in the Assets JSON.`);

    // Check primitive asset prices against Coingecko (correct price oracle config)
    const assetPriceUsd = assetPrice / 1e18;
    let coingeckoAssetPriceUsd;

    // Skip Coingecko price checks for some assets that don't exist on Coingecko
    const checkCoingeckoPrice = assetType == 0 || assetType == 1 || assetType == 4 || assetType == 14;

    if (checkCoingeckoPrice) {
      const url = `https://api.coingecko.com/api/v3/simple/token_price/${coingeckoNetwork}?contract_addresses=${assetAddress}&vs_currencies=usd&include_market_cap=false&include_24hr_vol=false&include_24hr_change=false&include_last_updated_at=true`;
      try {
        const { data } = await axios.get(url);
        coingeckoAssetPriceUsd = data[assetAddress.toLowerCase()].usd;

        console.log(
          `${asset.assetName} Asset type: ${assetType}, Asset price: ${assetPriceUsd}, Coingecko price: ${coingeckoAssetPriceUsd}`,
        );

        if (!approxEq(assetPriceUsd, coingeckoAssetPriceUsd)) {
          console.warn(
            `WARNING: ${asset.assetName} price doesn't match Coingecko. dHEDGE price ${assetPriceUsd}, Coingecko price ${coingeckoAssetPriceUsd}`,
          );
        }
      } catch (err: unknown) {
        if (err instanceof Error) {
          console.error(`WARNING: Error getting Coingecko price for ${asset.assetName}: ${err.message}`);
        }
        console.warn(`${asset.assetName} dHEDGE price ${assetPriceUsd}, Coingecko price N/A`);
      }
    } else {
      console.log(`${asset.assetName} Asset type: ${assetType}, Asset price: ${assetPriceUsd}, Coingecko price: N/A`);
    }
  }

  console.log("Asset checks complete!");
  console.log("_________________________________________");
};
