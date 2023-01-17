import { polygonChainData } from "../../../../config/chainData/polygon-data";
import { ArrakisLiquidityGaugeV4AssetGuardTest } from "../../common/arrakis/ArrakisLiquidityGaugeV4AssetGuardTest";

ArrakisLiquidityGaugeV4AssetGuardTest(
  "polygon",
  polygonChainData.arrakis,
  polygonChainData.assets.wmatic,
  polygonChainData.assets,
  polygonChainData.assetsBalanceOfSlot,
);
