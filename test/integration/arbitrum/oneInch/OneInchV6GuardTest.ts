import { runOneInchV6GuardTest } from "../../common/oneInch/OneInchV6GuardTest";
import { arbitrumChainData } from "../../../../config/chainData/arbitrumData";

runOneInchV6GuardTest({
  ...arbitrumChainData,
  chainId: 42161,
  aggregationRouterV6: arbitrumChainData.oneInch.v6Router,
  uniV2Factory: arbitrumChainData.uniswapV2.factory,
  uniV3Factory: arbitrumChainData.uniswapV3.factory,
});
