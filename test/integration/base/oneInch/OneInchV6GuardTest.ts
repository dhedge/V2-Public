import { runOneInchV6GuardTest } from "../../common/oneInch/OneInchV6GuardTest";
import { baseChainData } from "../../../../config/chainData/baseData";

runOneInchV6GuardTest({
  ...baseChainData,
  assets: { ...baseChainData.assets },
  chainId: 8453,
  aggregationRouterV6: baseChainData.oneInch.v6Router,
  uniV2Factory: baseChainData.uniswapV2.factory,
  uniV3Factory: baseChainData.uniswapV3.factory,
});
