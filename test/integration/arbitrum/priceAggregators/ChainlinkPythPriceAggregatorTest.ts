import { runChainlinkPythPriceAggregatorTest } from "../../common/priceAggregators/ChainlinkPythPriceAggregatorTest";
import { IOracleData } from "../../common/priceAggregators/ChainlinkPythPriceAggregatorTest";
import { arbitrumChainData } from "../../../../config/chainData/arbitrumData";

const oracleData: IOracleData = {
  onchainOracle: { oracleContract: arbitrumChainData.usdPriceFeeds.link, maxAge: 86400 },
  offchainOracle: {
    priceId: arbitrumChainData.pyth.priceIds.link,
    maxAge: 86500,
    minConfidenceRatio: 0,
  },
};

runChainlinkPythPriceAggregatorTest({
  tokenToTest: arbitrumChainData.assets.link,
  pythAddress: arbitrumChainData.pyth.priceFeedContract,
  oracleData: oracleData,
});
