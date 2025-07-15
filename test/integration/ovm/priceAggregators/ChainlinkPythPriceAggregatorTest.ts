import { runChainlinkPythPriceAggregatorTest } from "../../common/priceAggregators/ChainlinkPythPriceAggregatorTest";
import { ovmChainData } from "../../../../config/chainData/ovmData";
import { IOracleData } from "../../common/priceAggregators/ChainlinkPythPriceAggregatorTest";

const oracleData: IOracleData = {
  onchainOracle: { oracleContract: ovmChainData.usdPriceFeeds.eth, maxAge: 86400 },
  offchainOracle: {
    priceId: ovmChainData.pyth.priceIds.ethUsd,
    maxAge: 86500,
    minConfidenceRatio: 0,
  },
};

// Run tests for ETH/USD price feed
runChainlinkPythPriceAggregatorTest({
  tokenToTest: ovmChainData.assets.weth,
  pythAddress: ovmChainData.pyth.priceFeedContract,
  oracleData: oracleData,
});
