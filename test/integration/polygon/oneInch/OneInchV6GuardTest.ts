import { runOneInchV6GuardTest } from "../../common/oneInch/OneInchV6GuardTest";
import { polygonChainData } from "../../../../config/chainData/polygonData";

runOneInchV6GuardTest({
  ...polygonChainData,
  chainId: 137,
  aggregationRouterV6: polygonChainData.oneinch.v6Router,
  uniV2Factory: polygonChainData.uniswapV2.factory,
  uniV3Factory: polygonChainData.uniswapV3.factory,
  quickswapUniV2Factory: polygonChainData.quickswap.factoryV2,
});
