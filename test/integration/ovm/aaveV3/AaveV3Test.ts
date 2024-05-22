import { testAaveV3 } from "../../common/aaveV3/AaveV3Test";
import { ovmChainData } from "../../../../config/chainData/ovmData";

testAaveV3({
  ...ovmChainData,
  ...ovmChainData.aaveV3,
  rewardToken: ovmChainData.assets.op,
});
