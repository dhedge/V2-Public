import { ovmChainData } from "../../../../config/chainData/ovmData";
import { testSonneFinance } from "../../common/sonne/SonneFinanceTest";

const { sonne, assets, assetsBalanceOfSlot } = ovmChainData;

testSonneFinance({
  comptroller: sonne.comptroller,
  weth: {
    address: assets.weth,
    balanceOfSlot: assetsBalanceOfSlot.weth,
    cToken: sonne.cTokens.weth,
  },
  usdc: {
    address: assets.usdc,
    balanceOfSlot: assetsBalanceOfSlot.usdc,
    cToken: sonne.cTokens.usdc,
  },
  dai: {
    address: assets.dai,
    balanceOfSlot: assetsBalanceOfSlot.dai,
    cToken: sonne.cTokens.dai,
  },
});
