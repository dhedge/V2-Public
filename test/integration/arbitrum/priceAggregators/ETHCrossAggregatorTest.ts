import { runETHCrossAggregatorTest } from "../../common/priceAggregators/ETHCrossAggregatorTest";
import { arbitrumChainData } from "../../../../config/chainData/arbitrumData";

runETHCrossAggregatorTest({
  tokenToTest: arbitrumChainData.assets.wsteth,
  tokenEthPriceFeed: arbitrumChainData.ethPriceFeeds.wsteth,
  ethUsdPriceFeed: arbitrumChainData.usdPriceFeeds.eth,
});
