import { runOneInchV6GuardTest } from "../../common/oneInch/OneInchV6GuardTest";
import { polygonChainData } from "../../../../config/chainData/polygonData";

runOneInchV6GuardTest({
  ...polygonChainData,
  chainId: 137,
  aggregationRouterV6: polygonChainData.oneinch.v6Router,
});
