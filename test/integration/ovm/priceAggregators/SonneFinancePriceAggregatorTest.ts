import { runSonnePriceAggregatorTest } from "../../common/priceAggregators/SonneFinancePriceAggregatorTest";
import { ovmChainData } from "../../../../config/chainData/ovmData";

// Run tests for cUSDC and cDAI.
runSonnePriceAggregatorTest({
  comptroller: ovmChainData.sonne.comptroller,
  tokens: [
    {
      symbol: "cUSDC",
      address: ovmChainData.assets.usdc,
      cToken: ovmChainData.sonne.cTokens.usdc,
    },
    {
      symbol: "cDAI",
      address: ovmChainData.assets.dai,
      cToken: ovmChainData.sonne.cTokens.dai,
    },
  ],
});
