import { arbitrumChainData } from "../../../../config/chainData/arbitrumData";
import { testAaveV3 } from "../../common/aaveV3/AaveV3Test";

testAaveV3({
  ...arbitrumChainData,
  ...arbitrumChainData.aaveV3,
});
