import { testAaveV3WithWETH } from "../../common/aaveV3/AaveV3TestWithWETH";
import { ovmChainData } from "../../../../config/chainData/ovmData";

testAaveV3WithWETH({
  ...ovmChainData,
  ...ovmChainData.aaveV3,
});
