import { testAaveV3 } from "../../common/aaveV3/AaveV3Test";
import { polygonChainData } from "../../../../config/chainData/polygonData";

testAaveV3({
  ...polygonChainData,
  ...polygonChainData.aaveV3,
});
