import { aaveV3, assets, assetsBalanceOfSlot, zipswap } from "../../../config/chainData/ovm-data";
import { testAaveV3WithWETH } from "../common/AaveV3TestWithWETH";

testAaveV3WithWETH({
  network: "ovm",
  aaveLendingPool: aaveV3.lendingPool,
  swapRouter: zipswap.router,
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
