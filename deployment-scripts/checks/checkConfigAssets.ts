import axios from "axios";
import { assert } from "chai";
import csv from "csvtojson";
import { Contract } from "ethers";
import { HardhatRuntimeEnvironment } from "hardhat/types";

import { InitType } from "./initialize";
import { ICSVAsset } from "../types";

const approxEq = (v1: number, v2: number, diff = 0.01) => Math.abs(1 - v1 / v2) <= diff;

export const checkAssets = async (initializeData: InitType, hre: HardhatRuntimeEnvironment) => {
  const { network } = hre;
  // Coingecko API
  // https://www.coingecko.com/en/api/documentation - asset_platforms
  // asset_platforms
  const coingeckoNetwork = network.name == "polygon" ? "polygon-pos" : "optimistic-ethereum";

  const { versions, version, assetsFileName, balancerLps, poolFactoryProxy, balancerV2Vault, assetHandlerProxy } =
    initializeData;

  // Check Assets settings against latest Assets CSV file
  console.log("Checking assets..");

  const assets = versions[version].contracts.Assets;
  const csvAssets: ICSVAsset[] = await csv().fromFile(assetsFileName);

  // Check for any new assets in the asset CSV config
  for (const csvAsset of csvAssets) {
    let foundInVersions = false;
    for (const asset of assets) {
      if (csvAsset.assetAddress.toLowerCase() === asset.assetAddress.toLowerCase()) foundInVersions = true;
    }
    assert(foundInVersions, `Couldn't find ${csvAsset.assetName} address in published versions.json list.`);
  }

  // Check for any new assets in the Balancer JSON config
  if (balancerV2Vault) {
    for (const balancerLp of balancerLps) {
      console.log("Checking", balancerLp.name);
      let foundInVersions = false;
      for (const asset of assets) {
        if (balancerLp.address.toLowerCase() === asset.assetAddress.toLowerCase()) {
          foundInVersions = true;
          await checkBalancerLpAsset(hre, balancerLp, balancerV2Vault, poolFactoryProxy, assetHandlerProxy);
        }
      }
      assert(foundInVersions, `Couldn't find ${balancerLp.name} address in published versions.json list.`);
    }
  }

  for (const asset of assets) {
    const assetAddress = asset.assetAddress;
    const assetPrice = parseInt((await poolFactoryProxy.getAssetPrice(assetAddress)).toString());
    const assetType = parseInt((await poolFactoryProxy.getAssetType(assetAddress)).toString());

    assert(assetPrice > 0, `${asset.assetName} price is not above 0`);
    assert(
      assetType == parseInt(asset.assetType),
      `${asset.assetName} assetType mismatch. Deployed version ${version} assetType = ${asset.assetType}, Contract assetType = ${assetType}`,
    );

    let foundInCsv = false;

    // Reverse check Asset CSV config
    for (const csvAsset of csvAssets) {
      if (csvAsset.assetAddress == assetAddress) {
        foundInCsv = true;
        assert(
          assetType == csvAsset.assetType,
          `${asset.assetName} assetType mismatch. CSV assetType = ${csvAsset.assetType}, Contract assetType = ${assetType}`,
        );
      }
    }

    // Reverse check Balancer LP JSON config
    for (const balancerLp of balancerLps) {
      if (balancerLp.address.toLowerCase() === asset.assetAddress.toLowerCase()) {
        foundInCsv = true;
        assert(
          assetType == parseInt(balancerLp.assetType),
          `${asset.assetName} assetType mismatch. Balancer LP JSON assetType = ${balancerLp.assetType}, Contract assetType = ${assetType}`,
        );
      }
    }

    assert(
      foundInCsv,
      `Couldn't find ${asset.assetName} address in the Assets CSV, USD Assets CSV or Balancer JSON config.`,
    );

    // Check primitive asset prices against Coingecko (correct price oracle config)
    const assetPriceUsd = assetPrice / 1e18;
    let coingeckoAssetPriceUsd;

    // Skip Coingecko price checks for some assets that don't exist on Coingecko
    const checkCoingeckoPrice =
      !asset.assetName.includes("Balancer LP") &&
      !asset.assetName.includes("dUSD") &&
      (assetType == 0 || assetType == 1 || assetType == 4)
        ? true
        : false;

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
    }
  }

  console.log("Asset checks complete!");
  console.log("_________________________________________");
};

const checkBalancerLpAsset = async (
  hre: HardhatRuntimeEnvironment,
  balancerLp: Contract,
  balancerV2Vault: Contract,
  poolFactoryProxy: Contract,
  assetHandlerProxy: Contract,
) => {
  const { ethers, artifacts } = hre;
  const balancerLPAggregator = await assetHandlerProxy.priceAggregators(balancerLp.address);
  const BalancerV2LPAggregator = await artifacts.readArtifact("BalancerV2LPAggregator");
  const aggregator = await ethers.getContractAt(BalancerV2LPAggregator.abi, balancerLPAggregator);
  const BalancerV2Pool = await artifacts.readArtifact("IBalancerPool");
  const pool = await ethers.getContractAt(BalancerV2Pool.abi, balancerLp.address);
  const poolId = await pool.getPoolId();
  const poolTokens = (await balancerV2Vault.getPoolTokens(poolId))[0];
  const assetType = parseInt(await poolFactoryProxy.getAssetType(balancerLp.address));

  // check Balancer LP asset type configuration
  assert(assetType === balancerLp.assetType, `${balancerLp.name} deployed asset type mismatch with configuration.`);

  // get token weights
  let weights;
  if (balancerLp.type === "balancerLpToken") {
    // check Balancer LP token configuration
    assert(
      poolTokens.length === balancerLp.data.tokens.length,
      `${balancerLp.name} pool tokens length mismatch with configuration.`,
    );
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
    weights = await pool.getNormalizedWeights();
  }

  // pool token checks
  for (let i = 0; i < poolTokens.length; i++) {
    const aggregatorPoolToken = await aggregator.tokens(i);
    assert(
      aggregatorPoolToken.toLowerCase() === poolTokens[i].toLowerCase(),
      `${balancerLp.name} pool token address mismatch with deployment.`,
    );

    // check token decimals
    const IERC20 = await artifacts.readArtifact("IERC20Extended");
    const token = await ethers.getContractAt(IERC20.abi, poolTokens[i]);
    let aggregatorTokenDecimals;
    try {
      aggregatorTokenDecimals = await aggregator.tokenDecimals(i);
    } catch {
      // the old Balancer LP aggregator used `decimals` function for storing the underlying token decimals, not `tokenDecimals`
      const oldAggregator = await ethers.getContractAt(
        [
          {
            inputs: [{ internalType: "uint256", name: "", type: "uint256" }],
            name: "decimals",
            outputs: [{ internalType: "uint8", name: "", type: "uint8" }],
            stateMutability: "view",
            type: "function",
          },
        ],
        aggregator.address,
      );
      aggregatorTokenDecimals = await oldAggregator.decimals(i);
    }
    const decimals = await token.decimals();
    assert(decimals === aggregatorTokenDecimals, `${balancerLp.name} pool token decimals mismatch with deployment.`);

    if (balancerLp.type === "balancerLpToken") {
      // weighted pool - check token weight
      const aggregatorPoolWeights = await aggregator.weights(i);
      assert(
        aggregatorPoolWeights / 1e18 === weights[i] / 1e18,
        `${balancerLp.name} pool token weights mismatch with deployment.`,
      );
    }
  }
};
