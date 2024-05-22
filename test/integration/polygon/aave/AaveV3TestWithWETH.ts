import { testAaveV3WithWETH } from "../../common/aaveV3/AaveV3TestWithWETH";
import { polygonChainData } from "../../../../config/chainData/polygonData";

testAaveV3WithWETH({
  ...polygonChainData,
  ...polygonChainData.aaveV3,
});
