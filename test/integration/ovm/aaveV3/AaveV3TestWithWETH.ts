import { testAaveV3WithWETH } from "../../common/aaveV3/AaveV3TestWithWETH";

import { ovmChainData } from "../../../../config/chainData/ovmData";
const { aaveV3, assets, assetsBalanceOfSlot } = ovmChainData;

testAaveV3WithWETH({
  network: "ovm",
  aaveLendingPool: aaveV3.lendingPool,
  swapRouter: ovmChainData.velodrome.router,
  weth: {
    address: assets.weth,
    slotOfBalance: assetsBalanceOfSlot.weth,
    aToken: aaveV3.aTokens.weth,
    variableDebtToken: aaveV3.variableDebtTokens.weth,
  },
  usdc: {
    address: assets.usdc,
    slotOfBalance: assetsBalanceOfSlot.usdc,
    aToken: aaveV3.aTokens.usdc,
  },
  dai: {
    address: assets.dai,
    aToken: aaveV3.aTokens.dai,
    variableDebtToken: aaveV3.variableDebtTokens.dai,
    slotOfBalance: assetsBalanceOfSlot.dai,
  },
});
