import { polygonChainData } from "../../../../config/chainData/polygonData";
const { assets, assetsBalanceOfSlot, aaveV3 } = polygonChainData;
import { testAaveV3 } from "../../common/aaveV3/AaveV3Test";

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
    balanceOfSlot: assetsBalanceOfSlot.dai,
    aToken: aaveV3.aTokens.dai,
    varDebtToken: aaveV3.variableDebtTokens.dai,
  },
});
