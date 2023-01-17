import { ovmChainData } from "../../../../config/chainData/ovm-data";
import { ArrakisLiquidityGaugeV4AssetGuardTest } from "../../common/arrakis/ArrakisLiquidityGaugeV4AssetGuardTest";

ArrakisLiquidityGaugeV4AssetGuardTest(
  "ovm",
  ovmChainData.arrakis,
  ovmChainData.assets.op,
  ovmChainData.assets,
  ovmChainData.assetsBalanceOfSlot,
);
