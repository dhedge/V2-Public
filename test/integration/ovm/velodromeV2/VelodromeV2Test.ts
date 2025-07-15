import { runTests as runVelodromeV2LPAssetGuardTest } from "../../common/velodromeV2/VelodromeV2LPAssetGuardTest";
import { runTests as runVelodromeV2GaugeContractGuardTest } from "../../common/velodromeV2/VelodromeV2GaugeContractGuardTest";
import { runTests as runVelodromeLPAggregatorTest } from "../../common/velodromeV2/VelodromeLPAggregatorTest";
import { runTests as runVelodromeV2RouterGuardTest } from "../../common/velodromeV2/VelodromeV2RouterGuardTest";
import { runTests as runVelodromeV2TWAPAggregatorTest } from "../../common/velodromeV2/VelodromeV2TWAPAggregatorTest";
import { ovmChainData } from "../../../../config/chainData/ovmData";

const ovmTestParams = {
  ...ovmChainData,
  ...ovmChainData.velodromeV2,
  protocolToken: ovmChainData.velodromeV2.velo,
  VARIABLE_PROTOCOLTOKEN_USDC: ovmChainData.velodromeV2.VARIABLE_VELO_USDC,
};

runVelodromeV2LPAssetGuardTest(ovmTestParams);
runVelodromeV2GaugeContractGuardTest(ovmTestParams);
runVelodromeLPAggregatorTest(ovmTestParams);
runVelodromeV2RouterGuardTest(ovmTestParams);
runVelodromeV2TWAPAggregatorTest([
  {
    assetToTest: ovmChainData.assets.weth,
    veloV2Pair: ovmChainData.velodromeV2.VARIABLE_WETH_USDC.poolAddress,
    pairAsset: ovmChainData.assets.usdc,
    pairAssetPriceFeed: ovmChainData.usdPriceFeeds.usdc,
    coingeckoChainId: "optimistic-ethereum",
  },
]);
