import { runETHCrossAggregatorTest } from "../../common/priceAggregators/ETHCrossAggregatorTest";
import { polygonChainData } from "../../../../config/chainData/polygonData";

runETHCrossAggregatorTest({
  tokenToTest: polygonChainData.assets.ghst,
  tokenEthPriceFeed: polygonChainData.eth_price_feeds.ghst,
  ethUsdPriceFeed: polygonChainData.price_feeds.eth,
});
