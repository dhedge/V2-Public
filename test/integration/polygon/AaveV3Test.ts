import { aaveV3, assets, assetsBalanceOfSlot } from "../../../config/chainData/polygon-data";
import { testAaveV3 } from "../common/AaveV3Test";

testAaveV3({
  network: "polygon",
  aaveLendingPool: aaveV3.lendingPool,
  weth: {
    address: assets.weth,
  },
  usdt: {
    address: assets.usdt,
    balanceOfSlot: assetsBalanceOfSlot.usdt,
    aToken: aaveV3.aTokens.usdt,
  },
  usdc: {
    address: assets.usdc,
    balanceOfSlot: assetsBalanceOfSlot.usdc,
    aToken: aaveV3.aTokens.usdc,
  },
  dai: {
    address: assets.dai,
    aToken: aaveV3.aTokens.dai,
  },
});
