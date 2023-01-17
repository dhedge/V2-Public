import { ovmChainData } from "../../../config/chainData/ovm-data";
import { testAaveV3 } from "../common/AaveV3Test";

const { aaveV3, assets, assetsBalanceOfSlot } = ovmChainData;

testAaveV3({
  network: "ovm",
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
  aaveIncentivesController: aaveV3.incentivesController,
  rewardToken: {
    address: assets.op,
  },
});
