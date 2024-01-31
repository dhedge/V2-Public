import { runETHCrossAggregatorTest } from "../../common/priceAggregators/ETHCrossAggregatorTest";
import { polygonChainData } from "../../../../config/chainData/polygonData";

runETHCrossAggregatorTest({
  tokenToTest: polygonChainData.assets.ghst,
  tokenEthPriceFeed: polygonChainData.ethPriceFeeds.ghst,
  ethUsdPriceFeed: polygonChainData.usdPriceFeeds.eth,
});
