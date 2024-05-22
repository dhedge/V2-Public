import { testAaveV3WithWETH } from "../../common/aaveV3/AaveV3TestWithWETH";
import { arbitrumChainData } from "../../../../config/chainData/arbitrumData";

testAaveV3WithWETH({
  ...arbitrumChainData,
  ...arbitrumChainData.aaveV3,
});
