import { polygonChainData } from "../../../../config/chainData/polygonData";
const { sushi, assets, assetsBalanceOfSlot, aaveV3 } = polygonChainData;
import { testAaveV3WithWETH } from "../../common/aaveV3/AaveV3TestWithWETH";

testAaveV3WithWETH({
  network: "polygon",
  aaveLendingPool: aaveV3.lendingPool,
  swapRouter: sushi.router,
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
