import { runTests as runAerodromeLPAssetGuardTest } from "../../common/velodromeV2/VelodromeV2LPAssetGuardTest";
import { runTests as runAerodromeGaugeContractGuardTest } from "../../common/velodromeV2/VelodromeV2GaugeContractGuardTest";
import { runTests as runAerodromeLPAggregatorTest } from "../../common/velodromeV2/VelodromeLPAggregatorTest";
import { runTests as runAerodromeRouterGuardTest } from "../../common/velodromeV2/VelodromeV2RouterGuardTest";
import { runTests as runAerodromeTWAPAggregatorTest } from "../../common/velodromeV2/VelodromeV2TWAPAggregatorTest";
import { baseChainData } from "../../../../config/chainData/baseData";

const baseTestParams = {
  ...baseChainData,
  ...baseChainData.aerodrome,
  assets: { ...baseChainData.assets, usdt: "0xf99faf12efe98c6b67a4a96cbb5265af846d6319" }, // Fake USDT address (not used in these tests)
  protocolToken: baseChainData.aerodrome.aero,
  VARIABLE_PROTOCOLTOKEN_USDC: baseChainData.aerodrome.VARIABLE_AERO_USDC,
};

runAerodromeLPAssetGuardTest(baseTestParams);
runAerodromeGaugeContractGuardTest(baseTestParams);
runAerodromeLPAggregatorTest(baseTestParams);
runAerodromeRouterGuardTest(baseTestParams);

runAerodromeTWAPAggregatorTest([
  {
    assetToTest: baseChainData.assets.weth,
    veloV2Pair: baseChainData.aerodrome.VARIABLE_WETH_USDC.poolAddress,
    pairAsset: baseChainData.assets.usdc,
    pairAssetPriceFeed: baseChainData.usdPriceFeeds.usdc,
    coingeckoChainId: "base",
  },
]);
