import { runSonnePriceAggregatorSimulationTest } from "./SonneFinancePriceAggregatorSimulation";
import { ovmChainData } from "../../config/chainData/ovmData";

runSonnePriceAggregatorSimulationTest({
  token: {
    address: ovmChainData.assets.usdc,
    cToken: ovmChainData.sonne.cTokens.usdc,
  },
  startBlock: 112726625,
  numberOfBlocks: 100,
});

runSonnePriceAggregatorSimulationTest({
  token: {
    address: ovmChainData.assets.dai,
    cToken: ovmChainData.sonne.cTokens.dai,
  },
  startBlock: 112726625,
  numberOfBlocks: 100,
});
