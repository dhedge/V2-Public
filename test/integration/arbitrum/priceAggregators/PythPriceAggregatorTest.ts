import { arbitrumChainData } from "../../../../config/chainData/arbitrumData";
import { arbitrumProdData } from "../../../../deployment/arbitrum/deploymentData";
import { runPythPriceAggregatorTestTest } from "../../common/priceAggregators/PythPriceAggregatorTest";

runPythPriceAggregatorTestTest({
  // eslint-disable-next-line @typescript-eslint/no-non-null-assertion
  tokenToTest: arbitrumProdData.gmx!.virtualTokenResolver[1].virtualToken, // gmx SUI
  pythAddress: arbitrumChainData.pyth.priceFeedContract,
  // eslint-disable-next-line @typescript-eslint/no-non-null-assertion
  oracleData: arbitrumProdData.gmx!.virtualTokenResolver[1].pythOracleData,
  coingeckoTokenId: "sui",
});
