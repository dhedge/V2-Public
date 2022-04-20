import { aaveV3, assets, assetsBalanceOfSlot, sushi } from "../../../config/chainData/polygon-data";
import { testAaveV3WithWETH } from "../common/AaveV3TestWithWETH";

testAaveV3WithWETH({
  network: "polygon",
  aaveLendingPool: aaveV3.lendingPool,
  swapRouter: sushi.router,
  weth: {
    address: assets.weth,
    balanceOfSlot: assetsBalanceOfSlot.weth,
    aToken: aaveV3.aTokens.weth,
    variableDebtToken: aaveV3.variableDebtTokens.weth,
  },
  usdc: {
    address: assets.usdc,
    balanceOfSlot: assetsBalanceOfSlot.usdc,
    aToken: aaveV3.aTokens.usdc,
  },
  dai: {
    address: assets.dai,
    aToken: aaveV3.aTokens.dai,
    variableDebtToken: aaveV3.variableDebtTokens.dai,
  },
});
